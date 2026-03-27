<script lang="ts">
  import type { Dirspace, Repository } from './types';
  // Auth handled by PageLayout
  import { api } from './api';
  import { selectedInstallation, installationsLoading, currentVCSProvider } from './stores';
  import { repositoryService } from './services/repository-service';
  import PageLayout from './components/layout/PageLayout.svelte';
  import Card from './components/ui/Card.svelte';
  import ClickableCard from './components/ui/ClickableCard.svelte';
  import LinkCard from './components/ui/LinkCard.svelte';
  import EmptyState from './components/ui/EmptyState.svelte';
  import { onMount, onDestroy } from 'svelte';
  import { navigateToRun as navigateToRunUtil, navigateToRuns } from './utils/navigation';
  import { VCS_PROVIDERS } from './vcs/providers';
  import { LoadingSpinner } from './components';
  import { EXTERNAL_URLS } from './constants';

  // Note: Terraform summary functionality removed due to memory safety concerns
  // Large terraform outputs could crash browsers during summary extraction
  // TODO: Re-implement when server-side summary computation is available
  
  let workManifests: Dirspace[] = [];
  let repositories: Repository[] = [];
  let isLoadingWorkManifests: boolean = false;
  let isLoadingRepos: boolean = true; // Start as loading
  let error: string | null = null;

  // View mode state (Overview vs Search)
  let viewMode: 'overview' | 'search' = 'overview';
  
  // Get current VCS provider terminology
  $: currentProvider = $currentVCSProvider || 'github';
  $: terminology = VCS_PROVIDERS[currentProvider]?.terminology || VCS_PROVIDERS.github.terminology;

  // Recent failures
  let recentFailures: Dirspace[] = [];
  let isLoadingFailures: boolean = true; // Start as loading
  let hasLoadedFailures: boolean = false; // Track if we've ever loaded
  
  // Recent successes
  let recentSuccesses: Dirspace[] = [];
  let isLoadingSuccesses: boolean = true; // Start as loading
  let hasLoadedSuccesses: boolean = false; // Track if we've ever loaded
  
  // Active operations (running/pending)
  let activeOperations: Dirspace[] = [];
  let isLoadingActive: boolean = true; // Start as loading
  let hasLoadedActive: boolean = false; // Track if we've ever loaded
  let activeRefreshInterval: NodeJS.Timeout | null = null;
  
  // Active tab for recent activity
  let activeTab: 'active' | 'failures' | 'successes' = 'active';
  
  // Query-based filtering state (for Search mode)
  let searchQuery: string = '';
  let showQueryExamples: boolean = false;
  
  // Basic mode vs Advanced mode (for Search mode)
  let isBasicMode: boolean = true;
  
  // Pagination state
  let currentPage: number = 1;
  let pageSize: number = 20; // Runs per request
  let hasMoreResults: boolean = false;
  let isLoadingMore: boolean = false;
  let nextPageUrl: string | null = null; // URL for next page from Link header
  
  // Basic mode filter state
  let basicFilters = {
    repo: '',
    state: '',
    user: '',
    type: '',
    branch: '',
    dateRange: '',
    environment: '',
    workspace: ''
  };
  
  // Enhanced date range state
  let dateRangeMode: 'preset' | 'custom' = 'preset';
  let customStartDate: string = '';
  let customEndDate: string = '';
  
  // Repository grouping for non-overwhelming display
  let groupedRuns: Record<string, Dirspace[]> = {};
  let collapsedRepos: Set<string> = new Set();
  
  // Repository overview metrics
  interface RepoMetrics {
    name: string;
    successCount: number;
    runningCount: number;
    failedCount: number;
    lastApplied?: {
      user: string;
      workspace: string;
      date: string;
    };
  }
  let repoMetrics: RepoMetrics[] = [];
  let isLoadingMetrics: boolean = true; // Start as loading
  let hasLoadedMetrics: boolean = false; // Track if we've ever loaded

  // Repository filtering
  let repoFilter: string = '';
  let filteredRepoMetrics: RepoMetrics[] = [];
  
  // Repository pagination
  let repoCurrentPage: number = 1;
  let repoPageSize: number = 10;
  let paginatedRepoMetrics: RepoMetrics[] = [];
  
  // Terraform summary functionality removed for memory safety
  // TODO: Implement server-side summary computation to avoid client-side crashes

  // Get query from URL parameters (from hash-based routing)
  function getQueryFromURL(): string {
    if (typeof window !== 'undefined') {
      const hash = window.location.hash;
      // Extract query parameters from hash (e.g., #/runs?q=repo:name)
      const queryIndex = hash.indexOf('?');
      if (queryIndex !== -1) {
        const queryString = hash.substring(queryIndex + 1);
        const urlParams = new URLSearchParams(queryString);
        return urlParams.get('q') || '';
      }
    }
    return '';
  }
  
  // Handle URL changes (when navigating with query parameters)
  function handleURLChange(): void {
    const urlQuery = getQueryFromURL();
    searchQuery = urlQuery || '';
    
    // Parse repository filter from URL and set it in Basic mode dropdown
    if (urlQuery) {
      // Check for repo: prefix first
      const repoMatch = urlQuery.match(/repo:([^\s]+)/);
      if (repoMatch && repoMatch[1]) {
        basicFilters.repo = repoMatch[1];
      } else {
        // Clear repo filter if no repo: found in query
        basicFilters.repo = '';
      }
    } else {
      // Clear repo filter if no query
      basicFilters.repo = '';
    }
    
    if (urlQuery.trim()) {
      viewMode = 'search';
      if ($selectedInstallation) {
        loadRuns();
      }
    } else {
      viewMode = 'overview';
    }
  }

  // Listen for URL changes (hash changes)
  onMount(() => {
    // Initial URL check
    handleURLChange();
    
    // Listen for hash changes
    const handleHashChange = () => {
      handleURLChange();
    };
    
    window.addEventListener('hashchange', handleHashChange);
    
    return () => {
      window.removeEventListener('hashchange', handleHashChange);
    };
  });

  onDestroy(() => {
    stopActiveRefresh();
  });

  // Start/stop auto-refresh based on active tab
  $: if (activeTab === 'active' && $selectedInstallation) {
    if (!hasLoadedActive) {
      loadActiveOperations();
    }
    startActiveRefresh();
  } else {
    stopActiveRefresh();
  }
  
  // Load data when installation changes (with protection against redundant calls)
  let lastInstallationId: string | null = null;
  $: if ($selectedInstallation && $selectedInstallation.id !== lastInstallationId) {
    lastInstallationId = $selectedInstallation.id;
    initializeSearchQuery();
    loadRepositories();
    
    // Check if we have URL search parameters - if so, switch to search mode
    const urlQuery = getQueryFromURL();
    if (urlQuery.trim()) {
      viewMode = 'search';
      loadRuns();
    } else if (viewMode === 'overview') {
      loadRepoMetrics();
      loadRecentFailures();
      loadRecentSuccesses();
      loadActiveOperations();
      startActiveRefresh();
    } else {
      loadRuns();
    }
  } else if (!$selectedInstallation) {
    // Reset loading states when no installation is selected
    isLoadingRepos = false;
    isLoadingFailures = false;
    isLoadingSuccesses = false;
    isLoadingActive = false;
    isLoadingMetrics = false;
    stopActiveRefresh();
    lastInstallationId = null;
  }

  // Filter repositories based on search
  $: {
    if (repoFilter.trim()) {
      filteredRepoMetrics = repoMetrics.filter(repo => 
        repo.name.toLowerCase().includes(repoFilter.toLowerCase())
      );
    } else {
      filteredRepoMetrics = repoMetrics;
    }
    // Reset to first page when filter changes
    repoCurrentPage = 1;
  }
  
  // Paginate filtered repositories
  $: {
    const startIndex = (repoCurrentPage - 1) * repoPageSize;
    const endIndex = startIndex + repoPageSize;
    paginatedRepoMetrics = filteredRepoMetrics.slice(startIndex, endIndex);
  }
  
  // Calculate total pages for repositories
  $: totalRepoPages = Math.ceil(filteredRepoMetrics.length / repoPageSize);
  
  // Group runs by repository
  $: {
    groupedRuns = {};
    workManifests.forEach(manifest => {
      const repoName = manifest.repo;
      if (!groupedRuns[repoName]) {
        groupedRuns[repoName] = [];
      }
      groupedRuns[repoName].push(manifest);
    });
    
    // Sort runs within each repo by created_at desc
    Object.keys(groupedRuns).forEach(repoName => {
      groupedRuns[repoName].sort((a, b) => 
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      );
    });
  }

  async function loadRepositories(): Promise<void> {
    if (!$selectedInstallation) return;
    
    isLoadingRepos = true;
    try {
      const result = await repositoryService.loadRepositories($selectedInstallation);
      repositories = result.repositories;
      
      if (result.error) {
        console.error('Error loading repositories:', result.error);
      }
    } catch (err) {
      console.error('Error loading repositories:', err);
      repositories = [];
    } finally {
      isLoadingRepos = false;
    }
  }
  
  async function loadRepoMetrics(): Promise<void> {
    if (!$selectedInstallation) return;
    
    isLoadingMetrics = true;
    error = null;
    
    try {
      // Prepare run params for parallel loading
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      const dateFilter = thirtyDaysAgo.toISOString().split('T')[0];
      
      const params = { 
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        q: `created_at:${dateFilter}..`,
        limit: 100 // API appears to cap at 100 results regardless of limit requested
      };

      // Load repositories from cache and dirspaces in parallel
      const [reposResult, response] = await Promise.all([
        repositoryService.loadRepositories($selectedInstallation),
        api.getInstallationDirspaces($selectedInstallation.id, params)
      ]);
      
      const allRepos = reposResult.repositories;
      
      // Initialize metrics for ALL repositories (even if no runs)
      const metricsMap = new Map<string, RepoMetrics>();
      allRepos.forEach(repo => {
        metricsMap.set(repo.name, {
          name: repo.name,
          successCount: 0,
          runningCount: 0,
          failedCount: 0
        });
      });
      
      // Add run metrics for repos that have activity
      if (response && 'dirspaces' in response) {
        const dirspaces = response.dirspaces as Dirspace[];
        
        dirspaces.forEach((ds: Dirspace) => {
          const repoName = ds.repo;
          // Only process if this repo exists in our organization
          if (metricsMap.has(repoName)) {
            const metrics = metricsMap.get(repoName)!;
            
            // Count by state
            switch (ds.state) {
              case 'success':
                metrics.successCount++;
                break;
              case 'running':
                metrics.runningCount++;
                break;
              case 'failure':
                metrics.failedCount++;
                break;
            }
            
            // Track most recent apply operation
            if (ds.run_type === 'apply' && ds.state === 'success') {
              if (!metrics.lastApplied || new Date(ds.completed_at || ds.created_at) > new Date(metrics.lastApplied.date)) {
                metrics.lastApplied = {
                  user: ds.user || 'Unknown',
                  workspace: ds.workspace || ds.dir || 'default',
                  date: ds.completed_at || ds.created_at
                };
              }
            }
          }
        });
      } else {
      }
      
      repoMetrics = Array.from(metricsMap.values()).sort((a, b) => a.name.localeCompare(b.name));
      
    } catch (err) {
      console.error('Error loading repository metrics:', err);
      error = 'Failed to load repository metrics';
      repoMetrics = [];
    } finally {
      isLoadingMetrics = false;
      hasLoadedMetrics = true;
    }
  }

  async function loadRecentFailures(): Promise<void> {
    if (!$selectedInstallation) return;
    
    isLoadingFailures = true;
    
    try {
      const params = { 
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        q: 'state:failure',
        limit: 10
      };
      
      const response = await api.getInstallationDirspaces($selectedInstallation.id, params);
      
      if (response && 'dirspaces' in response) {
        recentFailures = response.dirspaces as Dirspace[];
      } else {
        recentFailures = [];
      }
      
    } catch (err) {
      console.error('Error loading recent failures:', err);
      recentFailures = [];
    } finally {
      isLoadingFailures = false;
      hasLoadedFailures = true;
    }
  }

  async function loadRecentSuccesses(): Promise<void> {
    if (!$selectedInstallation) return;
    
    isLoadingSuccesses = true;
    
    try {
      const params = { 
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        q: 'state:success',
        limit: 10
      };
      
      const response = await api.getInstallationDirspaces($selectedInstallation.id, params);
      
      if (response && 'dirspaces' in response) {
        recentSuccesses = response.dirspaces as Dirspace[];
      } else {
        recentSuccesses = [];
      }
      
    } catch (err) {
      console.error('Error loading recent successes:', err);
      recentSuccesses = [];
    } finally {
      isLoadingSuccesses = false;
      hasLoadedSuccesses = true;
    }
  }

  async function loadActiveOperations(): Promise<void> {
    if (!$selectedInstallation) return;
    
    isLoadingActive = true;
    
    try {
      const params = { 
        tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
        q: 'state:running or state:pending or state:queued',
        limit: 20
      };
      
      const response = await api.getInstallationDirspaces($selectedInstallation.id, params);
      
      if (response && 'dirspaces' in response) {
        activeOperations = response.dirspaces as Dirspace[];
      } else {
        activeOperations = [];
      }
      
    } catch (err) {
      console.error('Error loading active operations:', err);
      activeOperations = [];
    } finally {
      isLoadingActive = false;
      hasLoadedActive = true;
    }
  }

  function startActiveRefresh(): void {
    if (activeRefreshInterval) return;
    
    activeRefreshInterval = setInterval(async () => {
      if (activeTab === 'active' && $selectedInstallation) {
        await loadActiveOperations();
      }
    }, 10000); // Refresh every 10 seconds
  }

  function stopActiveRefresh(): void {
    if (activeRefreshInterval) {
      clearInterval(activeRefreshInterval);
      activeRefreshInterval = null;
    }
  }
  
  async function loadRuns(loadMore: boolean = false): Promise<void> {
    if (!$selectedInstallation) return;
    
    if (loadMore) {
      isLoadingMore = true;
    } else {
      isLoadingWorkManifests = true;
      // Reset for new search
      currentPage = 1;
      hasMoreResults = false;
      nextPageUrl = null;
    }
    error = null;
    
    try {
      let response;
      
      if (loadMore && nextPageUrl) {
        // Use the next page URL directly from the Link header
        // Make direct fetch request to the URL provided by Link header
        const fetchResponse = await fetch(nextPageUrl, {
          method: 'GET',
          headers: {
            'Content-Type': 'application/json',
          },
          credentials: 'include',
        });
        
        if (!fetchResponse.ok) {
          throw new Error(`HTTP ${fetchResponse.status}: ${fetchResponse.statusText}`);
        }
        
        const rawResponse = await fetchResponse.json();
        
        // Parse Link headers from the response
        const linkHeader = fetchResponse.headers.get('Link') || fetchResponse.headers.get('link');
        let linkHeaders: Record<string, string> | null = null;
        if (linkHeader) {
          // Simple parsing of Link header
          linkHeaders = {};
          const parts = linkHeader.split(/,\s*(?=<)/);
          for (const part of parts) {
            const match = part.match(/<([^>]+)>;\s*rel="([^"]+)"/);
            if (match) {
              linkHeaders[match[2]] = match[1];
            }
          }
        }
        
        // Format response to match our expected structure
        response = {
          dirspaces: rawResponse.dirspaces || [],
          hasMore: linkHeaders?.next !== undefined,
          linkHeaders
        };
      } else {
        // Build query for initial load
        let query = searchQuery.trim();
        
        const params: Record<string, unknown> = { 
          tz: Intl.DateTimeFormat().resolvedOptions().timeZone,
          limit: pageSize
        };
        
        if (query) {
          params.q = query;
        }
        
        response = await api.getInstallationDirspaces($selectedInstallation.id, params);
      }
      
      if (response && 'dirspaces' in response) {
        const dirspaces = response.dirspaces as Dirspace[];
        
        
        // Use Link header to determine if there are more results
        hasMoreResults = response.hasMore;
        
        // Fix double slash issue in the URL if present
        if (response.linkHeaders?.next) {
          nextPageUrl = response.linkHeaders.next.replace('//api/', '/api/');
        } else {
          nextPageUrl = null;
        }
        
        const actualResults = dirspaces;
        
        if (loadMore) {
          // Append to existing results
          workManifests = [...workManifests, ...actualResults];
        } else {
          // Replace results for new search
          workManifests = actualResults;
        }
        
        currentPage = loadMore ? currentPage + 1 : 1;
        

      } else {
        if (!loadMore) {
          workManifests = [];
          hasMoreResults = false;
        }
      }
      
    } catch (err) {
      console.error('Error loading runs:', err);
      error = 'Failed to load runs';
      if (!loadMore) {
        workManifests = [];
        hasMoreResults = false;
      }
    } finally {
      if (loadMore) {
        isLoadingMore = false;
      } else {
        isLoadingWorkManifests = false;
      }
    }
  }

  // Update URL with query parameter (for hash-based routing)
  function updateURLWithQuery(query: string): void {
    if (typeof window !== 'undefined') {
      const hash = window.location.hash;
      const hashParts = hash.split('?');
      const basePath = hashParts[0]; // e.g., #/runs
      
      if (query) {
        const newHash = `${basePath}?q=${encodeURIComponent(query)}`;
        window.history.replaceState({}, '', newHash);
      } else {
        window.history.replaceState({}, '', basePath);
      }
    }
  }

  // Search functionality
  async function performSearch(): Promise<void> {
    updateURLWithQuery(searchQuery);
    await loadRuns(false); // false = new search, not loading more
  }
  
  // Load more functionality
  async function loadMoreRuns(): Promise<void> {
    await loadRuns(true); // true = load more, append to existing
  }

  function clearSearch(): void {
    searchQuery = '';
    // Also reset enhanced date range state for consistency
    dateRangeMode = 'preset';
    customStartDate = '';
    customEndDate = '';
    resetPagination();
    updateURLWithQuery('');
    loadRuns(false);
  }

  // Initialize search query from URL
  function initializeSearchQuery(): void {
    const urlQuery = getQueryFromURL();
    searchQuery = urlQuery || '';
    
    // Parse repository filter from URL and set it in Basic mode dropdown
    if (urlQuery) {
      // Check for repo: prefix first
      const repoMatch = urlQuery.match(/repo:([^\s]+)/);
      if (repoMatch && repoMatch[1]) {
        basicFilters.repo = repoMatch[1];
      } else if (repositories.some(r => r.name === urlQuery)) {
        // If the query matches a repository name exactly, treat it as a repo filter
        basicFilters.repo = urlQuery;
      }
    }
  }

  // Quick search helpers
  function addQuickFilter(filter: string): void {
    // Preserve existing repository filter when adding quick filters
    const existingRepoFilter = extractRepoFilter(searchQuery);
    if (existingRepoFilter) {
      searchQuery = `repo:${existingRepoFilter} and ${filter}`;
    } else {
      searchQuery = filter;
    }
    resetPagination();
    performSearch();
  }

  // Helper to extract repository filter from existing query
  function extractRepoFilter(query: string): string | null {
    const repoMatch = query.match(/repo:([^\s]+)/);
    return repoMatch ? repoMatch[1] : null;
  }

  // Basic mode helpers
  function buildQueryFromBasicFilters(): string {
    const filters = [];
    
    if (basicFilters.repo) filters.push(`repo:${basicFilters.repo}`);
    if (basicFilters.state) filters.push(`state:${basicFilters.state}`);
    if (basicFilters.user) filters.push(`user:${basicFilters.user}`);
    if (basicFilters.type) filters.push(`type:${basicFilters.type}`);
    if (basicFilters.branch) filters.push(`branch:${basicFilters.branch}`);
    if (basicFilters.environment) filters.push(`environment:${basicFilters.environment}`);
    if (basicFilters.workspace) filters.push(`workspace:${basicFilters.workspace}`);
    // Handle different date range modes
    if (dateRangeMode === 'preset' && basicFilters.dateRange) {
      // Convert friendly date range to query format
      const today = new Date();
      switch (basicFilters.dateRange) {
        case 'today':
          filters.push(`created_at:${today.toISOString().split('T')[0]}..`);
          break;
        case 'yesterday':
          const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000);
          filters.push(`created_at:${yesterday.toISOString().split('T')[0]}..${today.toISOString().split('T')[0]}`);
          break;
        case 'week':
          const weekAgo = new Date(today.getTime() - 7 * 24 * 60 * 60 * 1000);
          filters.push(`created_at:${weekAgo.toISOString().split('T')[0]}..`);
          break;
        case 'month':
          const monthAgo = new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000);
          filters.push(`created_at:${monthAgo.toISOString().split('T')[0]}..`);
          break;
        case '3months':
          const threeMonthsAgo = new Date(today.getTime() - 90 * 24 * 60 * 60 * 1000);
          filters.push(`created_at:${threeMonthsAgo.toISOString().split('T')[0]}..`);
          break;
        case '6months':
          const sixMonthsAgo = new Date(today.getTime() - 180 * 24 * 60 * 60 * 1000);
          filters.push(`created_at:${sixMonthsAgo.toISOString().split('T')[0]}..`);
          break;
      }
    } else if (dateRangeMode === 'custom' && (customStartDate || customEndDate)) {
      // Custom date range - handle datetime-local format
      let startStr = '';
      let endStr = '';
      
      if (customStartDate) {
        // datetime-local format is YYYY-MM-DDTHH:MM
        // Convert to API format: YYYY-MM-DD HH:MM
        startStr = customStartDate.replace('T', ' ');
      }
      
      if (customEndDate) {
        endStr = customEndDate.replace('T', ' ');
      }
      
      if (startStr && endStr) {
        // Use quotes when time is included
        if (startStr.includes(' ') || endStr.includes(' ')) {
          filters.push(`"created_at:${startStr}..${endStr}"`);
        } else {
          filters.push(`created_at:${startStr}..${endStr}`);
        }
      } else if (startStr) {
        if (startStr.includes(' ')) {
          filters.push(`"created_at:${startStr}.."`);
        } else {
          filters.push(`created_at:${startStr}..`);
        }
      } else if (endStr) {
        if (endStr.includes(' ')) {
          filters.push(`"created_at:..${endStr}"`);
        } else {
          filters.push(`created_at:..${endStr}`);
        }
      }
    }
    
    return filters.join(' and ');
  }

  // Utility functions for active operations display
  function formatDuration(milliseconds: number): string {
    const seconds = Math.floor(milliseconds / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    
    if (hours > 0) return `${hours}h ${minutes % 60}m`;
    if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
    return `${seconds}s`;
  }

  function formatDateTime(dateString: string): string {
    const date = new Date(dateString);
    
    // Format: "Jan 24, 2025 3:45 PM"
    const options: Intl.DateTimeFormatOptions = {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
      hour12: true
    };
    
    return date.toLocaleString('en-US', options);
  }

  function getStateColor(state: string): string {
    switch (state) {
      case 'success': return 'bg-[var(--sg-success-bg)] text-[var(--sg-success)] border-[var(--sg-success)]';
      case 'failure': return 'bg-[var(--sg-error-bg)] text-[var(--sg-error)] border-[var(--sg-error)]';
      case 'running': return 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] border-[var(--sg-accent)]';
      case 'pending': 
      case 'queued': return 'bg-[var(--sg-warning-bg)] text-[var(--sg-warning)] border-[var(--sg-warning)]';
      default: return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)] border-[var(--sg-border)]';
    }
  }

  function getStateIcon(state: string): string {
    switch (state) {
      case 'success': return '✅';
      case 'failure': return '❌';
      case 'running': return '🔄';
      case 'pending': 
      case 'queued': return '⏳';
      default: return '❓';
    }
  }

  function performBasicSearch(): void {
    searchQuery = buildQueryFromBasicFilters();
    resetPagination();
    performSearch();
  }

  function clearBasicFilters(): void {
    basicFilters = {
      repo: '',
      state: '',
      user: '',
      type: '',
      branch: '',
      dateRange: '',
      environment: '',
      workspace: ''
    };
    // Reset enhanced date range state
    dateRangeMode = 'preset';
    customStartDate = '';
    customEndDate = '';
    
    searchQuery = '';
    resetPagination();
    updateURLWithQuery('');
    loadRuns();
  }

  function switchToAdvancedMode(): void {
    // Convert basic filters to query string for advanced mode
    searchQuery = buildQueryFromBasicFilters();
    resetPagination();
    isBasicMode = false;
  }

  function switchToBasicMode(): void {
    // Preserve repository filter when switching to basic mode
    const existingRepoFilter = extractRepoFilter(searchQuery);
    resetPagination();
    if (existingRepoFilter) {
      basicFilters.repo = existingRepoFilter;
      searchQuery = `repo:${existingRepoFilter}`;
    } else {
      searchQuery = '';
      clearBasicFilters();
    }
    isBasicMode = true;
  }

  function toggleRepoCollapse(repoName: string): void {
    if (collapsedRepos.has(repoName)) {
      collapsedRepos.delete(repoName);
    } else {
      collapsedRepos.add(repoName);
    }
    collapsedRepos = collapsedRepos; // Trigger reactivity
  }
  
  function changeRepoPage(page: number): void {
    if (page >= 1 && page <= totalRepoPages) {
      repoCurrentPage = page;
    }
  }
  
  function getRepoPageNumbers(): number[] {
    const pages: number[] = [];
    const maxPagesToShow = 5;
    
    let startPage = Math.max(1, repoCurrentPage - Math.floor(maxPagesToShow / 2));
    let endPage = Math.min(totalRepoPages, startPage + maxPagesToShow - 1);
    
    // Adjust start if we're near the end
    if (endPage - startPage < maxPagesToShow - 1) {
      startPage = Math.max(1, endPage - maxPagesToShow + 1);
    }
    
    for (let i = startPage; i <= endPage; i++) {
      pages.push(i);
    }
    
    return pages;
  }

  function viewRepoRuns(repoName: string): void {
    navigateToRuns(`repo:${encodeURIComponent(repoName)}`);
  }

  // Reset pagination when search query changes
  function resetPagination(): void {
    currentPage = 1;
    hasMoreResults = false;
    nextPageUrl = null;
  }

  // Store search context when navigating to run detail
  function navigateToRun(runId: string): void {
    // Store the current search context so we can return to it
    if (viewMode === 'search' && searchQuery) {
      sessionStorage.setItem('lastRunSearch', `q=${encodeURIComponent(searchQuery)}`);
    } else {
      // Clear any previous search context when coming from overview
      sessionStorage.removeItem('lastRunSearch');
    }
    navigateToRunUtil(runId);
  }
  
  // Generate installation-scoped href for run links
  function getRunHref(query: string): string {
    if ($selectedInstallation) {
      return `#/i/${$selectedInstallation.id}/runs?q=${encodeURIComponent(query)}`;
    }
    return `#/runs?q=${encodeURIComponent(query)}`;
  }
  
  // Generate installation-scoped href for run detail
  function getRunDetailHref(runId: string): string {
    if ($selectedInstallation) {
      return `#/i/${$selectedInstallation.id}/runs/${runId}`;
    }
    return `#/runs/${runId}`;
  }
  
</script>

<PageLayout 
  activeItem="runs" 
  title={basicFilters.repo ? `Repository Runs` : "Runs"} 
  subtitle={basicFilters.repo ? `Runs for ${basicFilters.repo}` : "Search and manage Terraform operations across all repositories"}
>
  <!-- Back Button (when viewing a specific repository) -->
  {#if basicFilters.repo}
    <div class="mb-6">
      <button
        on:click={() => {
          basicFilters.repo = '';
          searchQuery = '';
          updateURLWithQuery('');
          loadRuns();
        }}
        class="inline-flex items-center px-3 md:px-4 py-2 text-sm font-medium text-[var(--sg-text-dim)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-md hover:bg-[var(--sg-bg-2)] hover:text-[var(--sg-text-muted)] focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-[var(--sg-accent)] transition-colors shadow-sm"
      >
        <svg class="w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
        </svg>
        Back to All Runs
      </button>
    </div>
  {/if}

  <!-- View Mode Selector (only show when not viewing a specific repository) -->
  {#if !basicFilters.repo}
    <div class="mb-6">
      <div class="flex items-center space-x-1 bg-[var(--sg-bg-2)] rounded-lg p-1 w-full sm:w-fit">
        <button
          on:click={() => {
            viewMode = 'overview';
            searchQuery = '';
            updateURLWithQuery('');
            loadRepoMetrics();
            loadRecentFailures();
            loadRecentSuccesses();
          }}
          class="flex-1 sm:flex-initial px-3 py-2 text-xs sm:text-sm font-medium rounded-md transition-colors {viewMode === 'overview' ? 'bg-[var(--sg-bg-1)] text-[var(--sg-accent)] shadow-sm' : 'text-[var(--sg-text-dim)] hover:text-[var(--sg-text)]'}"
        >
          🏠 Overview
        </button>
        <button
          on:click={() => {
            viewMode = 'search';
            if (!searchQuery.trim()) {
              // If no search query, don't load runs yet - wait for user input
              isBasicMode = true;
            } else {
              loadRuns();
            }
          }}
          class="flex-1 sm:flex-initial px-3 py-2 text-xs sm:text-sm font-medium rounded-md transition-colors {viewMode === 'search' ? 'bg-[var(--sg-bg-1)] text-[var(--sg-accent)] shadow-sm' : 'text-[var(--sg-text-dim)] hover:text-[var(--sg-text)]'}"
        >
          🔍 Search
        </button>
      </div>
    </div>
  {/if}

  {#if $installationsLoading}
    <div class="flex justify-center items-center py-12">
      <LoadingSpinner size="lg" centered={false} />
      <span class="ml-3 text-[var(--sg-text-dim)]">Loading organizations...</span>
    </div>
  {:else if !$selectedInstallation}
    <!-- Demo Mode Message -->
    <Card padding="lg" class="border-[var(--sg-accent)] bg-[var(--sg-accent-bg)]">
      <div class="text-center">
        <div class="flex justify-center mb-4">
          <svg class="w-16 h-16 text-[var(--sg-accent)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M9 19l3 3m0 0l3-3m-3 3V10" />
          </svg>
        </div>
        <h3 class="text-xl font-semibold text-[var(--sg-accent)] mb-2">Demo Mode - Runs</h3>
        <p class="text-[var(--sg-accent)] mb-6">
          You're viewing the runs page in demo mode. Once you connect a {VCS_PROVIDERS[currentProvider].displayName} {terminology.organization.toLowerCase()}, you'll see your real run history and can track Terraform operations.
        </p>
        
        <div class="grid gap-4 mb-6">
          <div class="text-sm text-[var(--sg-accent)] bg-[var(--sg-bg-1)] rounded-lg p-4 border border-[var(--sg-accent)]">
            <div class="font-semibold mb-2">What you'll see here:</div>
            <ul class="text-left space-y-1">
              <li>• Real-time run status (running, success, failure)</li>
              <li>• Terraform plan and apply operations</li>
              <li>• Advanced search with filters (user, branch, environment)</li>
              <li>• Detailed logs and outputs for each run</li>
              <li>• Run statistics and trends</li>
            </ul>
          </div>
        </div>
        
        <ClickableCard 
          padding="sm"
          hover={true}
          on:click={() => window.location.hash = '#/getting-started'}
          aria-label="Go to getting started to connect a repository"
          class="inline-block bg-[var(--sg-bg-1)] border-[var(--sg-accent)] hover:border-[var(--sg-accent)]"
        >
          <div class="flex items-center space-x-2 text-[var(--sg-accent)]">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.746 0 3.332.477 4.5 1.253v13C19.832 18.477 18.246 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
            </svg>
            <span class="font-medium">Connect Your First Repository</span>
          </div>
        </ClickableCard>
      </div>
    </Card>
  {:else if error}
        <div class="bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-md p-4 mb-6">
          <div class="flex">
            <div class="flex-shrink-0">
              <svg class="h-5 w-5 text-[var(--sg-error)]" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
              </svg>
            </div>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-[var(--sg-error)]">Error</h3>
              <div class="mt-2 text-sm text-[var(--sg-error)]">
                <p>{error}</p>
              </div>
            </div>
          </div>
        </div>
      {/if}

      {#if viewMode === 'overview'}
      <!-- OVERVIEW MODE -->
      <div class="space-y-6">
        <!-- Recent Activity Tabbed Section -->
        <div class="bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-lg shadow overflow-hidden">
          <!-- Tab Headers -->
          <div class="border-b border-[var(--sg-border)]">
            <nav class="flex flex-col sm:flex-row sm:space-x-0" aria-label="Recent Activity">
              <button
                on:click={() => activeTab = 'active'}
                class="flex-1 py-3 px-2 sm:px-4 md:px-6 text-xs sm:text-sm font-medium text-center sm:border-b-2 border-l-4 sm:border-l-0 transition-colors {activeTab === 'active' ? 'border-[var(--sg-accent)] text-[var(--sg-accent)] bg-[var(--sg-accent-bg)]' : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)]'}"
              >
                <div class="flex items-center justify-center flex-wrap gap-1">
                  <span class="hidden sm:inline mr-1">🔄</span>
                  <span>Active</span>
                  <span class="hidden lg:inline">Operations</span>
                  {#if activeOperations.length > 0}
                    <span class="ml-1 inline-flex items-center px-1.5 py-0.5 rounded-full text-xs font-medium bg-[var(--sg-accent-bg)] text-[var(--sg-accent)]">
                      {activeOperations.length}
                    </span>
                  {/if}
                </div>
              </button>
              <button
                on:click={() => activeTab = 'failures'}
                class="flex-1 py-3 px-2 sm:px-4 md:px-6 text-xs sm:text-sm font-medium text-center sm:border-b-2 border-l-4 sm:border-l-0 transition-colors {activeTab === 'failures' ? 'border-[var(--sg-error)] text-[var(--sg-error)] bg-[var(--sg-error-bg)]' : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)]'}"
              >
                <div class="flex items-center justify-center flex-wrap gap-1">
                  <span class="hidden sm:inline mr-1">🚨</span>
                  <span>Recent</span>
                  <span>Failures</span>
                </div>
              </button>
              <button
                on:click={() => activeTab = 'successes'}
                class="flex-1 py-3 px-2 sm:px-4 md:px-6 text-xs sm:text-sm font-medium text-center sm:border-b-2 border-l-4 sm:border-l-0 transition-colors {activeTab === 'successes' ? 'border-[var(--sg-success)] text-[var(--sg-success)] bg-[var(--sg-success-bg)]' : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)]'}"
              >
                <div class="flex items-center justify-center flex-wrap gap-1">
                  <span class="hidden sm:inline mr-1">✅</span>
                  <span>Recent</span>
                  <span>Successes</span>
                </div>
              </button>
            </nav>
          </div>

          <!-- Tab Content -->
          <div class="p-4 sm:p-6">
            {#if activeTab === 'active'}
              <!-- Active Operations Content -->
              <div class="mb-4">
                <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                  <div>
                    <h2 class="text-base md:text-lg font-semibold text-[var(--sg-accent)]">Active Operations</h2>
                    <p class="text-xs md:text-sm text-[var(--sg-accent)]">Running and pending Terraform operations</p>
                  </div>
                  <div class="flex items-center space-x-2 text-xs md:text-sm text-[var(--sg-text-dim)]">
                    <div class="w-2 h-2 bg-[var(--sg-success)] rounded-full animate-pulse"></div>
                    <span>Auto-refreshing</span>
                  </div>
                </div>
              </div>

              {#if isLoadingActive && !hasLoadedActive}
                <div class="flex justify-center items-center py-8">
                  <LoadingSpinner size="md" centered={false} />
                  <span class="ml-3 text-[var(--sg-text-dim)]">Loading active operations...</span>
                </div>
              {:else if activeOperations.length > 0}

                <div class="space-y-3">
                  {#each activeOperations as operation}
                    {@const createdAt = new Date(operation.created_at)}
                    {@const now = new Date()}
                    {@const duration = now.getTime() - createdAt.getTime()}
                    
                    <LinkCard
                      href={getRunDetailHref(operation.id)}
                      padding="md"
                      hover={true}
                      on:click={(e) => {
                        // Allow middle-click and Ctrl/Cmd+click to open in new tab
                        if (e.button !== 0 || e.ctrlKey || e.metaKey) {
                          return;
                        }
                        e.preventDefault();
                        navigateToRunUtil(operation.id);
                      }}
                      aria-label="View operation {operation.run_type} in {operation.repo}/{operation.dir}"
                      class="bg-[var(--sg-bg-0)] hover:bg-[var(--sg-accent-bg)] border border-[var(--sg-border)] hover:border-[var(--sg-accent)]"
                    >
                      <div class="flex items-center justify-between">
                        <div class="flex-1 min-w-0">
                          <div class="mb-2">
                            <div class="flex flex-col sm:flex-row sm:items-start gap-2">
                              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium border flex-shrink-0 self-start {getStateColor(operation.state)}">
                                {getStateIcon(operation.state)} {operation.state.toUpperCase()}
                              </span>
                              <div class="flex-1 min-w-0">
                                <div class="text-xs sm:text-sm font-medium text-[var(--sg-text)]">
                                  {operation.run_type}
                                </div>
                                <div class="text-xs sm:text-sm text-[var(--sg-text-dim)] break-words">
                                  {operation.repo}/{operation.dir}
                                </div>
                              </div>
                            </div>
                          </div>
                          
                          <div class="text-xs text-[var(--sg-text-dim)] space-y-0.5">
                            <div>Started {formatDateTime(operation.created_at)}</div>
                            <div>Duration: {formatDuration(duration)}</div>
                            {#if operation.workspace && operation.workspace !== 'default'}
                              <div>Workspace: {operation.workspace}</div>
                            {/if}
                            {#if operation.environment}
                              <div>Environment: {operation.environment}</div>
                            {/if}
                          </div>

                        </div>
                        
                        <div class="flex items-center ml-2 sm:ml-4">
                          <svg class="w-4 h-4 text-[var(--sg-text-dim)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                          </svg>
                        </div>
                      </div>
                    </LinkCard>
                  {/each}
                </div>
              {:else}
                <div class="text-center py-8">
                  <p class="text-[var(--sg-text-dim)] text-sm">
                    No active Terraform operations running right now. When operations start, they'll appear here.
                  </p>
                </div>
              {/if}

            {:else if activeTab === 'failures'}
              <!-- Failures Content -->
              <div class="flex items-center justify-between mb-4">
                <div>
                  <h2 class="text-lg font-semibold text-[var(--sg-error)]">Recent Failures</h2>
                  <p class="text-sm text-[var(--sg-error)]">Latest failed runs that need attention</p>
                </div>
                {#if recentFailures.length > 0}
                  <a 
                    href={getRunHref('state:failure')}
                    class="text-sm text-[var(--sg-error)] hover:text-[var(--sg-error)] font-medium"
                  >
                    View all failures →
                  </a>
                {/if}
              </div>

              {#if isLoadingFailures}
                <div class="flex justify-center py-8">
                  <LoadingSpinner size="sm" color="error" centered={false} />
                </div>
              {:else if recentFailures.length === 0 && hasLoadedFailures}
                <div class="text-center py-8">
                  <div class="text-4xl mb-2">✅</div>
                  <p class="text-[var(--sg-error)] font-medium">No recent failures</p>
                  <p class="text-sm text-[var(--sg-error)] mt-1">All runs are running smoothly</p>
                </div>
              {:else}
                <div class="space-y-3">
                  {#each recentFailures.slice(0, 5) as failure}
                    <a 
                      href={getRunDetailHref(failure.id)}
                      on:click={(e) => {
                        // Allow middle-click and Ctrl/Cmd+click to open in new tab
                        if (e.button !== 0 || e.ctrlKey || e.metaKey) {
                          return;
                        }
                        e.preventDefault();
                        navigateToRun(failure.id);
                      }}
                      class="block w-full text-left p-4 bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-lg hover:bg-[var(--sg-error-bg)] hover:border-[var(--sg-error)] transition-colors cursor-pointer"
                    >
                      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                        <div class="flex-1">
                          <!-- Repository and Type -->
                          <div class="flex flex-wrap items-center gap-x-2 gap-y-1 mb-1">
                            <span class="font-medium text-[var(--sg-error)]">{failure.repo}</span>
                            <!-- Plan/Apply Badge for failures -->
                            {#if failure.run_type === 'plan'}
                              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-error-bg)] text-[var(--sg-error)] border border-[var(--sg-error)]" title="Click to view run details">
                                📋 Plan
                              </span>
                            {:else if failure.run_type === 'apply'}
                              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-error-bg)] text-[var(--sg-error)] border border-[var(--sg-error)]">
                                🚀 Apply
                              </span>
                            {:else}
                              <span class="text-sm text-[var(--sg-error)]">{failure.run_type}</span>
                            {/if}
                            
                            <!-- Drift Detection Indicator for failures -->
                            {#if failure.kind === 'drift'}
                              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-warning-bg)] text-[var(--sg-warning)] border border-[var(--sg-warning)]">
                                🔍 Drift
                              </span>
                            {/if}
                          </div>
                          
                          <!-- Branch and Directory -->
                          <div class="text-sm text-[var(--sg-error)] mb-1">
                            {failure.branch}
                            {#if failure.dir}
                              <span class="text-xs text-[var(--sg-error)]"> • </span>
                              <span class="text-xs text-[var(--sg-error)] font-mono">{failure.dir}</span>
                            {/if}
                            {#if failure.workspace && failure.workspace !== 'default'}
                              <span class="text-xs text-[var(--sg-error)]"> • </span>
                              <span class="text-xs text-[var(--sg-error)]">workspace: {failure.workspace}</span>
                            {/if}
                            {#if failure.environment}
                              <span class="text-xs text-[var(--sg-error)]"> • </span>
                              <span class="text-xs text-[var(--sg-error)]">env: {failure.environment}</span>
                            {/if}
                          </div>
                          
                          <!-- Timestamp and User -->
                          <div class="text-xs text-[var(--sg-error)]">
                            Failed {formatDateTime(failure.created_at)}
                            {#if failure.user}
                              • by {failure.user}
                            {/if}
                          </div>
                        </div>
                        
                        <!-- Status Badge and Arrow -->
                        <div class="flex items-center space-x-2 self-start sm:self-center">
                          <span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-[var(--sg-error-bg)] text-[var(--sg-error)]">
                            Failed
                          </span>
                          <svg class="w-4 h-4 text-[var(--sg-error)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                          </svg>
                        </div>
                      </div>
                    </a>
                  {/each}
                </div>
              {/if}
            {:else}
              <!-- Successes Content -->
              <div class="flex items-center justify-between mb-4">
                <div>
                  <h2 class="text-lg font-semibold text-[var(--sg-success)]">Recent Successes</h2>
                  <p class="text-sm text-[var(--sg-success)]">Latest successful runs</p>
                </div>
                {#if recentSuccesses.length > 0}
                  <a 
                    href={getRunHref('state:success')}
                    class="text-sm text-[var(--sg-success)] hover:text-[var(--sg-success)] font-medium"
                  >
                    View all successes →
                  </a>
                {/if}
              </div>

              {#if isLoadingSuccesses}
                <div class="flex justify-center py-8">
                  <LoadingSpinner size="sm" color="success" centered={false} />
                </div>
              {:else if recentSuccesses.length === 0 && hasLoadedSuccesses}
                <EmptyState title="No recent successes" description="No successful runs found recently" />
              {:else}
                <div class="space-y-3">
                  {#each recentSuccesses.slice(0, 5) as success}
                    <a 
                      href={getRunDetailHref(success.id)}
                      on:click={(e) => {
                        // Allow middle-click and Ctrl/Cmd+click to open in new tab
                        if (e.button !== 0 || e.ctrlKey || e.metaKey) {
                          return;
                        }
                        e.preventDefault();
                        navigateToRun(success.id);
                      }}
                      class="block w-full text-left p-4 bg-[var(--sg-success-bg)] border border-[var(--sg-success)] rounded-lg hover:bg-[var(--sg-success-bg)] hover:border-[var(--sg-success)] transition-colors cursor-pointer"
                    >
                      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                        <div class="flex-1">
                          <!-- Repository and Type -->
                          <div class="flex flex-wrap items-center gap-x-2 gap-y-1 mb-1">
                            <span class="font-medium text-[var(--sg-success)]">{success.repo}</span>
                            <!-- Plan/Apply Badge for successes -->
                            {#if success.run_type === 'plan'}
                              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)] border border-[var(--sg-success)]" title="Click to view run details">
                                📋 Plan
                              </span>
                            {:else if success.run_type === 'apply'}
                              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)] border border-[var(--sg-success)]">
                                🚀 Apply
                              </span>
                            {:else}
                              <span class="text-sm text-[var(--sg-success)]">{success.run_type}</span>
                            {/if}
                            
                            <!-- Drift Detection Indicator for successes -->
                            {#if success.kind === 'drift'}
                              <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-warning-bg)] text-[var(--sg-warning)] border border-[var(--sg-warning)]">
                                🔍 Drift
                              </span>
                            {/if}
                          </div>
                          
                          <!-- Branch and Directory -->
                          <div class="text-sm text-[var(--sg-success)] mb-1">
                            {success.branch}
                            {#if success.dir}
                              <span class="text-xs text-[var(--sg-success)]"> • </span>
                              <span class="text-xs text-[var(--sg-success)] font-mono">{success.dir}</span>
                            {/if}
                            {#if success.workspace && success.workspace !== 'default'}
                              <span class="text-xs text-[var(--sg-success)]"> • </span>
                              <span class="text-xs text-[var(--sg-success)]">workspace: {success.workspace}</span>
                            {/if}
                            {#if success.environment}
                              <span class="text-xs text-[var(--sg-success)]"> • </span>
                              <span class="text-xs text-[var(--sg-success)]">env: {success.environment}</span>
                            {/if}
                          </div>
                          
                          <!-- Timestamp and User -->
                          <div class="text-xs text-[var(--sg-success)]">
                            Completed {formatDateTime(success.created_at)}
                            {#if success.user}
                              • by {success.user}
                            {/if}
                          </div>
                        </div>
                        
                        <!-- Status Badge and Arrow -->
                        <div class="flex items-center space-x-2 self-start sm:self-center">
                          <span class="inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)]">
                            Success
                          </span>
                          <svg class="w-4 h-4 text-[var(--sg-success)]" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                          </svg>
                        </div>
                      </div>
                    </a>
                  {/each}
                </div>
              {/if}
            {/if}
          </div>
        </div>

        <!-- Repository Filter -->
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-lg font-semibold text-[var(--sg-text)]">Repositories</h2>
            <p class="text-sm text-[var(--sg-text-dim)]">Based on the most recent 100 runs from the last 30 days</p>
          </div>
          <div class="w-64">
            <input
              type="text"
              bind:value={repoFilter}
              placeholder="Filter repositories..."
              class="w-full px-3 py-2 border border-[var(--sg-border)] rounded-md text-sm bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-[var(--sg-accent)]"
            />
          </div>
        </div>

        <!-- Repository List -->
        {#if isLoadingMetrics}
          <LoadingSpinner size="md" />
        {:else if paginatedRepoMetrics.length === 0 && filteredRepoMetrics.length === 0 && hasLoadedMetrics}
          <div class="card-bg rounded-lg shadow">
            <EmptyState
              icon="mdi:inbox-outline"
              title={repoFilter ? 'No repositories match your filter' : 'No repositories found'}
              description={repoFilter ? 'Try adjusting your search terms' : 'No runs found in the last 30 days'}
            />
          </div>
        {:else}
          <div class="card-bg rounded-lg shadow overflow-hidden">
            <!-- Table Header -->
            <div class="bg-[var(--sg-bg-0)] px-4 md:px-6 py-3 border-b border-[var(--sg-border)]">
              <div class="hidden md:grid grid-cols-12 gap-4 text-xs font-medium text-[var(--sg-text-muted)] uppercase tracking-wider">
                <div class="col-span-4">Repository</div>
                <div class="col-span-2 text-center">Success</div>
                <div class="col-span-2 text-center">Failed</div>
                <div class="col-span-2 text-center">Running</div>
                <div class="col-span-2 text-center">Last Deploy</div>
              </div>
            </div>

            <!-- Repository Rows -->
            <div class="divide-y divide-[var(--sg-border)]">
              {#each paginatedRepoMetrics as repo}
                <div 
                  class="px-6 py-4 hover:bg-[var(--sg-bg-2)] cursor-pointer transition-colors"
                  on:click={() => viewRepoRuns(repo.name)}
                  on:keydown={(e) => e.key === 'Enter' && viewRepoRuns(repo.name)}
                  tabindex="0"
                  role="button"
                  aria-label="View runs for {repo.name}"
                >
                  <div class="flex flex-col md:grid md:grid-cols-12 md:gap-4 md:items-center space-y-3 md:space-y-0">
                    <!-- Repository Name -->
                    <div class="md:col-span-4">
                      <div class="flex items-center">
                        <svg class="w-4 h-4 text-[var(--sg-text-dim)] mr-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                        </svg>
                        <div>
                          <div class="font-medium text-[var(--sg-text)]">{repo.name}</div>
                          <div class="text-sm text-[var(--sg-text-dim)]">
                            {repo.successCount + repo.failedCount + repo.runningCount} total runs
                          </div>
                        </div>
                      </div>
                    </div>

                    <!-- Mobile: Status counts in a row with labels -->
                    <div class="flex justify-around md:hidden">
                      <!-- Success Count -->
                      <div class="text-center">
                        <div class="text-xs text-[var(--sg-text-dim)] mb-1">Success</div>
                        <div class="text-lg font-semibold text-[var(--sg-success)]">{repo.successCount}</div>
                      </div>
                      <!-- Failed Count -->
                      <div class="text-center">
                        <div class="text-xs text-[var(--sg-text-dim)] mb-1">Failed</div>
                        <div class="text-lg font-semibold {repo.failedCount > 0 ? 'text-[var(--sg-error)]' : 'text-[var(--sg-text-dim)]'}">{repo.failedCount}</div>
                      </div>
                      <!-- Running Count -->
                      <div class="text-center">
                        <div class="text-xs text-[var(--sg-text-dim)] mb-1">Running</div>
                        <div class="text-lg font-semibold {repo.runningCount > 0 ? 'text-[var(--sg-accent)]' : 'text-[var(--sg-text-dim)]'}">{repo.runningCount}</div>
                      </div>
                    </div>

                    <!-- Desktop: Status counts without labels (headers provide context) -->
                    <!-- Success Count -->
                    <div class="hidden md:block col-span-2 text-center">
                      <div class="text-lg font-semibold text-[var(--sg-success)]">{repo.successCount}</div>
                    </div>

                    <!-- Failed Count -->
                    <div class="hidden md:block col-span-2 text-center">
                      <div class="text-lg font-semibold {repo.failedCount > 0 ? 'text-[var(--sg-error)]' : 'text-[var(--sg-text-dim)]'}">{repo.failedCount}</div>
                    </div>

                    <!-- Running Count -->
                    <div class="hidden md:block col-span-2 text-center">
                      <div class="text-lg font-semibold {repo.runningCount > 0 ? 'text-[var(--sg-accent)]' : 'text-[var(--sg-text-dim)]'}">{repo.runningCount}</div>
                    </div>

                    <!-- Last Run -->
                    <div class="col-span-2 text-center">
                      <div class="text-xs text-[var(--sg-text-dim)] mb-1 md:hidden">Last Deploy</div>
                      {#if repo.lastApplied}
                        <div class="text-sm">
                          <div class="font-medium text-[var(--sg-text)]">{formatDateTime(repo.lastApplied.date)}</div>
                          <div class="text-xs text-[var(--sg-text-dim)]">by {repo.lastApplied.user}</div>
                        </div>
                      {:else}
                        <div class="text-sm text-[var(--sg-text-dim)]">No recent applies</div>
                      {/if}
                    </div>
                  </div>
                </div>
              {/each}
            </div>
            
            <!-- Pagination Controls -->
            {#if totalRepoPages > 1}
              <div class="bg-[var(--sg-bg-0)] px-6 py-3 border-t border-[var(--sg-border)]">
                <div class="flex items-center justify-between">
                  <div class="text-sm text-[var(--sg-text-muted)]">
                    Showing {(repoCurrentPage - 1) * repoPageSize + 1} to {Math.min(repoCurrentPage * repoPageSize, filteredRepoMetrics.length)} of {filteredRepoMetrics.length} repositories
                  </div>
                  <div class="flex items-center space-x-1">
                    <!-- Previous Button -->
                    <button
                      on:click={() => changeRepoPage(repoCurrentPage - 1)}
                      disabled={repoCurrentPage === 1}
                      class="p-2 rounded hover:bg-[var(--sg-bg-2)] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                      aria-label="Previous page"
                    >
                      <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                      </svg>
                    </button>
                    
                    <!-- Page Numbers -->
                    {#if repoCurrentPage > 3}
                      <button
                        on:click={() => changeRepoPage(1)}
                        class="px-3 py-1 text-sm rounded hover:bg-[var(--sg-bg-2)] transition-colors"
                      >
                        1
                      </button>
                      {#if repoCurrentPage > 4}
                        <span class="px-2 text-[var(--sg-text-dim)]">...</span>
                      {/if}
                    {/if}
                    
                    {#each getRepoPageNumbers() as page}
                      <button
                        on:click={() => changeRepoPage(page)}
                        class="px-3 py-1 text-sm rounded transition-colors {page === repoCurrentPage ? 'bg-[var(--sg-accent-button)] text-white' : 'hover:bg-[var(--sg-bg-2)]'}"
                      >
                        {page}
                      </button>
                    {/each}
                    
                    {#if repoCurrentPage < totalRepoPages - 2}
                      {#if repoCurrentPage < totalRepoPages - 3}
                        <span class="px-2 text-[var(--sg-text-dim)]">...</span>
                      {/if}
                      <button
                        on:click={() => changeRepoPage(totalRepoPages)}
                        class="px-3 py-1 text-sm rounded hover:bg-[var(--sg-bg-2)] transition-colors"
                      >
                        {totalRepoPages}
                      </button>
                    {/if}
                    
                    <!-- Next Button -->
                    <button
                      on:click={() => changeRepoPage(repoCurrentPage + 1)}
                      disabled={repoCurrentPage === totalRepoPages}
                      class="p-2 rounded hover:bg-[var(--sg-bg-2)] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                      aria-label="Next page"
                    >
                      <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                      </svg>
                    </button>
                  </div>
                </div>
              </div>
            {/if}
          </div>
        {/if}
      </div>
      {:else}
      <!-- SEARCH MODE -->
      <div class="space-y-6">
        <!-- Search Interface -->
        <div class="card-bg rounded-lg shadow p-4 sm:p-6">
          <div class="mb-4">
            <div class="flex flex-col gap-3">
              <!-- Title and Back Button Row -->
              <div class="flex items-center justify-between">
                <h3 class="text-sm font-semibold text-[var(--sg-accent)]">🔍 Search Runs</h3>
                <button
                  on:click={() => navigateToRuns()}
                  class="text-xs sm:text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)]"
                >
                  ← Back to Overview
                </button>
              </div>
              
              <!-- Mode Toggle Row -->
              <div class="flex items-center justify-center sm:justify-start gap-2">
                <span class="text-xs text-[var(--sg-text-dim)]">Mode:</span>
                <div class="flex rounded-md shadow-sm" role="group">
                  <button
                    on:click={switchToBasicMode}
                    class="px-3 py-1.5 text-xs font-medium rounded-l-md transition-colors {isBasicMode ? 'bg-[var(--sg-accent-button)] text-white' : 'bg-[var(--sg-bg-1)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)] border border-[var(--sg-border)]'}"
                  >
                    Basic
                  </button>
                  <button
                    on:click={switchToAdvancedMode}
                    class="px-3 py-1.5 text-xs font-medium rounded-r-md transition-colors {!isBasicMode ? 'bg-[var(--sg-accent-button)] text-white' : 'bg-[var(--sg-bg-1)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)] border border-[var(--sg-border)]'} {isBasicMode ? 'border-l border-[var(--sg-border)]' : ''}"
                  >
                    Advanced
                  </button>
                </div>
              </div>
            </div>

            {#if isBasicMode}
              <!-- Basic Mode: Dropdown Filters -->
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
                <!-- Repository Filter -->
                <div>
                  <label for="repo-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">Repository</label>
                  <select id="repo-filter" bind:value={basicFilters.repo} class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]">
                    <option value="">All repositories</option>
                    {#if isLoadingRepos}
                      <option value="" disabled>Loading repositories...</option>
                    {:else}
                      {#each repositories as repo}
                        <option value={repo.name}>{repo.name}</option>
                      {/each}
                    {/if}
                  </select>
                </div>

                <!-- Status Filter -->
                <div>
                  <label for="status-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">Status</label>
                  <select id="status-filter" bind:value={basicFilters.state} class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]">
                    <option value="">Any status</option>
                    <option value="success">✅ Success</option>
                    <option value="failure">❌ Failed</option>
                    <option value="running">🔄 Running</option>
                    <option value="aborted">⏸️ Aborted</option>
                    <option value="queued">⏳ Queued</option>
                  </select>
                </div>

                <!-- Type Filter -->
                <div>
                  <label for="type-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">Operation Type</label>
                  <select id="type-filter" bind:value={basicFilters.type} class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]">
                    <option value="">Any type</option>
                    <option value="plan">📋 Plan</option>
                    <option value="apply">🚀 Apply</option>
                  </select>
                </div>

                <!-- Enhanced Date Range Filter -->
                <div class="relative">
                  <div class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">Time Period</div>
                  
                  <!-- Date Range Mode Selector with Inline Preset Dropdown -->
                  <div class="flex items-center space-x-1 mb-2">
                    <button
                      type="button"
                      on:click={() => dateRangeMode = 'preset'}
                      class="px-2 py-1 text-xs border rounded {dateRangeMode === 'preset' ? 'bg-[var(--sg-accent-bg)] border-[var(--sg-accent)] text-[var(--sg-accent)]' : 'bg-[var(--sg-bg-1)] border-[var(--sg-border)] text-[var(--sg-text-dim)] hover:bg-[var(--sg-bg-2)]'}"
                    >
                      Presets
                    </button>
                    <button
                      type="button"
                      on:click={() => dateRangeMode = 'custom'}
                      class="px-2 py-1 text-xs border rounded {dateRangeMode === 'custom' ? 'bg-[var(--sg-accent-bg)] border-[var(--sg-accent)] text-[var(--sg-accent)]' : 'bg-[var(--sg-bg-1)] border-[var(--sg-border)] text-[var(--sg-text-dim)] hover:bg-[var(--sg-bg-2)]'}"
                    >
                      Custom
                    </button>
                    
                    <!-- Preset Dropdown (inline with buttons) -->
                    {#if dateRangeMode === 'preset'}
                      <select bind:value={basicFilters.dateRange} class="flex-1 px-2 py-1 text-xs border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]">
                        <option value="">All time</option>
                        <option value="today">Last 24 hours</option>
                        <option value="yesterday">Last 48 hours</option>
                        <option value="week">Last 7 days</option>
                        <option value="month">Last 30 days</option>
                        <option value="3months">Last 3 months</option>
                        <option value="6months">Last 6 months</option>
                      </select>
                    {/if}
                  </div>
                  
                  <!-- Custom Date Range Mode -->
                  {#if dateRangeMode === 'custom'}
                    <div class="space-y-2">
                      <div>
                        <label for="custom-start-date" class="block text-xs text-[var(--sg-text-dim)] mb-1">From date & time (optional)</label>
                        <input
                          id="custom-start-date"
                          type="datetime-local"
                          bind:value={customStartDate}
                          class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]"
                        />
                      </div>
                      <div>
                        <label for="custom-end-date" class="block text-xs text-[var(--sg-text-dim)] mb-1">To date & time (optional)</label>
                        <input
                          id="custom-end-date"
                          type="datetime-local"
                          bind:value={customEndDate}
                          class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]"
                        />
                      </div>
                      <div class="text-xs text-[var(--sg-text-dim)]">
                        <p>Leave blank for open-ended ranges</p>
                        <p class="mt-1">Examples: 2024-01-15 14:30 or just 2024-01-15</p>
                      </div>
                    </div>
                  {/if}
                </div>

                <!-- User Filter -->
                <div>
                  <label for="user-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">User</label>
                  <input
                    id="user-filter"
                    type="text"
                    bind:value={basicFilters.user}
                    placeholder="e.g., josh"
                    class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder:text-[var(--sg-text-dim)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]"
                  />
                </div>

                <!-- Branch Filter -->
                <div>
                  <label for="branch-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">Branch</label>
                  <input
                    id="branch-filter"
                    type="text"
                    bind:value={basicFilters.branch}
                    placeholder="e.g., main"
                    class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder:text-[var(--sg-text-dim)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]"
                  />
                </div>

                <!-- Environment Filter -->
                <div>
                  <label for="environment-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">{$currentVCSProvider === 'gitlab' ? 'GitLab' : 'GitHub'} Environment</label>
                  <input
                    id="environment-filter"
                    type="text"
                    bind:value={basicFilters.environment}
                    placeholder="e.g., production"
                    class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder:text-[var(--sg-text-dim)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]"
                  />
                </div>

                <!-- Workspace Filter -->
                <div>
                  <label for="workspace-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">Workspace</label>
                  <input
                    id="workspace-filter"
                    type="text"
                    bind:value={basicFilters.workspace}
                    placeholder="e.g., default"
                    class="w-full px-2 py-1 text-sm border border-[var(--sg-border)] rounded bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder:text-[var(--sg-text-dim)] focus:outline-none focus:ring-1 focus:ring-[var(--sg-accent)]"
                  />
                </div>
              </div>

              <!-- Basic Mode Actions -->
              <div class="flex items-center space-x-2">
                <button
                  on:click={performBasicSearch}
                  disabled={isLoadingWorkManifests}
                  class="px-4 py-2 bg-[var(--sg-accent-button)] text-white text-sm rounded-md hover:bg-[var(--sg-accent-button-hover)] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                >
                  {#if isLoadingWorkManifests}
                    <LoadingSpinner size="sm" color="white" centered={false} />
                  {:else}
                    Search
                  {/if}
                </button>
                <button
                  on:click={clearBasicFilters}
                  class="px-3 py-2 border border-[var(--sg-border)] text-[var(--sg-text-dim)] text-sm rounded-md bg-[var(--sg-bg-1)] hover:bg-[var(--sg-bg-2)] transition-colors"
                >
                  Clear All
                </button>
              </div>
            {:else}
              <!-- Advanced Mode: Direct Query Input -->
              <div class="space-y-4">
                <div>
                  <label for="search-query" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-2">
                    Search Query
                    <span class="text-[var(--sg-text-dim)] font-normal">(Use Terrateam query syntax: repo:name, state:success, user:josh, etc.)</span>
                  </label>
                  <input
                    id="search-query"
                    type="text"
                    bind:value={searchQuery}
                    placeholder="e.g., repo:myapp state:failure"
                    class="w-full px-3 py-2 border border-[var(--sg-border)] rounded-md bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder:text-[var(--sg-text-dim)] focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-[var(--sg-accent)]"
                    on:keydown={(e) => e.key === 'Enter' && performSearch()}
                  />
                </div>
                
                <!-- Quick Filter Buttons -->
                <div class="flex flex-wrap gap-2 mb-3 md:mb-0">
                  <span class="text-xs font-medium text-[var(--sg-text-muted)] self-center">Quick filters:</span>
                  <button on:click={() => addQuickFilter('state:failure')} class="px-2 py-1 bg-[var(--sg-error-bg)] text-[var(--sg-error)] text-xs rounded hover:bg-[var(--sg-error-bg)] transition-colors">
                    ❌ Failures
                  </button>
                  <button on:click={() => addQuickFilter('state:running')} class="px-2 py-1 bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] text-xs rounded hover:bg-[var(--sg-accent-bg)] transition-colors">
                    🔄 Running
                  </button>
                  <button on:click={() => addQuickFilter('type:apply')} class="px-2 py-1 bg-[var(--sg-success-bg)] text-[var(--sg-success)] text-xs rounded hover:bg-[var(--sg-success-bg)] transition-colors">
                    🚀 Applies
                  </button>
                  <button on:click={() => addQuickFilter('type:plan')} class="px-2 py-1 bg-[var(--sg-purple-bg)] text-[var(--sg-purple)] text-xs rounded hover:bg-[var(--sg-purple-bg)] transition-colors">
                    📋 Plans
                  </button>
                </div>

                <!-- Advanced Mode Actions -->
                <div class="flex items-center justify-between">
                  <div class="flex items-center space-x-2">
                    <button
                      on:click={performSearch}
                      disabled={isLoadingWorkManifests}
                      class="px-4 py-2 bg-[var(--sg-accent-button)] text-white text-sm rounded-md hover:bg-[var(--sg-accent-button-hover)] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                    >
                      {#if isLoadingWorkManifests}
                        <LoadingSpinner size="sm" color="white" centered={false} />
                      {:else}
                        Search
                      {/if}
                    </button>
                    <button
                      on:click={clearSearch}
                      class="px-3 py-2 border border-[var(--sg-border)] text-[var(--sg-text-dim)] text-sm rounded-md bg-[var(--sg-bg-1)] hover:bg-[var(--sg-bg-2)] transition-colors"
                    >
                      Clear All
                    </button>
                  </div>
                  <button
                    on:click={() => showQueryExamples = !showQueryExamples}
                    class="text-xs text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] underline"
                  >
                    {showQueryExamples ? 'Hide Examples' : 'Show Query Examples'}
                  </button>
                </div>

                <!-- Query Examples -->
                {#if showQueryExamples}
                  <div class="mt-4 p-4 bg-[var(--sg-bg-0)] rounded-lg border border-[var(--sg-border)]">
                    <h4 class="text-sm font-semibold text-[var(--sg-text)] mb-3">Tag Query Language (TQL) Examples</h4>
                    <div class="space-y-4 text-xs">
                      <!-- Basic Queries -->
                      <div>
                        <div class="font-medium text-[var(--sg-text-muted)] mb-2">Basic Queries:</div>
                        <div class="space-y-1 text-[var(--sg-text-dim)]">
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">pr:123</code> - Match pull request #123</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">state:failure</code> - Failed runs (options: running, success, failure, aborted, queued)</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">repo:infrastructure</code> - Operations in infrastructure repository</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">user:josh</code> - Operations by user josh</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">type:apply</code> - Apply operations (options: plan, apply)</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">kind:pr</code> - Pull request operations (options: pr, drift)</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">branch:main</code> - Operations on main branch</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">workspace:production</code> - Operations in production workspace</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">dir:infra/s3</code> - Operations that processed the infra/s3 directory</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">environment:production</code> - Operations in production {$currentVCSProvider === 'gitlab' ? 'GitLab' : 'GitHub'} environment</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">environment:</code> - Operations with no {$currentVCSProvider === 'gitlab' ? 'GitLab' : 'GitHub'} environment specified</div>
                        </div>
                      </div>
                      
                      <!-- Date Queries -->
                      <div>
                        <div class="font-medium text-[var(--sg-text-muted)] mb-2">Date & Time Queries:</div>
                        <div class="space-y-1 text-[var(--sg-text-dim)]">
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">created_at:2024-01-15</code> - Operations on January 15, 2024</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">created_at:2024-01-01..</code> - Operations since January 1, 2024</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">created_at:2024-01-01..2024-01-31</code> - Operations in January 2024</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">"created_at:2024-01-15 14:30"</code> - Operations at specific time (quotes required)</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">"created_at:2024-01-15 09:00..2024-01-15 17:00"</code> - Operations between specific times</div>
                        </div>
                      </div>

                      <!-- Sorting & Complex Queries -->
                      <div>
                        <div class="font-medium text-[var(--sg-text-muted)] mb-2">Sorting & Complex Examples:</div>
                        <div class="space-y-1 text-[var(--sg-text-dim)]">
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">sort:asc</code> - Sort by created_at ascending (options: asc, desc)</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">state:failure and repo:infrastructure</code> - Failed operations in infrastructure repo</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">user:josh and created_at:2024-01-01..</code> - Josh's operations since Jan 1</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">state:success and (user:josh or user:alex)</code> - Successful ops by josh or alex</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">branch:main and environment:production and type:apply</code> - Production applies from main</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">created_at:2024-01-01.. and kind:drift and sort:desc</code> - Recent drift operations</div>
                          <div><code class="bg-[var(--sg-bg-1)] px-2 py-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">dir:infra/s3 and dir:infra/iam and kind:pr</code> - PR operations affecting S3 and IAM</div>
                        </div>
                      </div>
                    </div>
                    <div class="mt-3 text-xs text-[var(--sg-text-dim)]">
                      <strong>Note:</strong> Use <code class="bg-[var(--sg-bg-1)] px-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">and</code>, <code class="bg-[var(--sg-bg-1)] px-1 rounded border border-[var(--sg-border)] text-[var(--sg-text)]">or</code>, and parentheses to combine queries. Date/time queries with spaces require quotes.
                    </div>
                  </div>
                {/if}
              </div>
            {/if}
          </div>
        </div>

        <!-- Search Results -->
        {#if isLoadingWorkManifests}
          <LoadingSpinner size="md" />
        {:else if workManifests.length === 0}
          <div class="card-bg rounded-lg shadow">
            <EmptyState
              icon="mdi:inbox-outline"
              title="No runs found"
              description={searchQuery
                ? `No runs match your search: ${searchQuery}`
                : 'Try adjusting your search criteria or time range.'}
            >
            <p class="mt-3 text-sm text-[var(--sg-text-dim)]">
              Need help? <a href={EXTERNAL_URLS.SLACK} target="_blank" rel="noopener noreferrer" class="text-[var(--sg-accent)] hover:underline">Join our Slack community</a>
            </p>
            </EmptyState>
          </div>
        {:else}
          <!-- Results Summary -->
          <div class="text-sm text-[var(--sg-text-dim)] mb-4">
            Showing {workManifests.length} run{workManifests.length !== 1 ? 's' : ''} 
            {#if searchQuery}
              matching: <code class="px-1 py-0.5 bg-[var(--sg-bg-2)] rounded text-xs text-[var(--sg-text)]">{searchQuery}</code>
            {/if}
            • Grouped by repository
          </div>

          <!-- Grouped Results by Repository -->
          <div class="space-y-4">
            {#each Object.keys(groupedRuns).sort() as repoName}
              <div class="bg-[var(--sg-bg-1)] rounded-lg shadow border border-[var(--sg-border)] overflow-hidden">
                <!-- Repository Header -->
                <button
                  on:click={() => toggleRepoCollapse(repoName)}
                  class="w-full px-4 md:px-6 py-3 md:py-4 bg-[var(--sg-accent-bg)] border-b border-[var(--sg-accent)] flex items-center justify-between hover:bg-[var(--sg-accent-bg)] transition-colors"
                >
                  <div class="flex items-center flex-wrap gap-2">
                    <svg class="w-5 h-5 text-[var(--sg-accent)] flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
                    </svg>
                    <h3 class="text-base sm:text-lg font-medium text-[var(--sg-accent)]">{repoName}</h3>
                    <span class="px-2.5 py-1 bg-[var(--sg-accent-bg)]/50 text-[var(--sg-accent)] text-xs rounded-full whitespace-nowrap">
                      {groupedRuns[repoName].length} run{groupedRuns[repoName].length !== 1 ? 's' : ''}
                    </span>
                  </div>
                  <svg 
                    class="w-5 h-5 text-[var(--sg-accent)] transition-transform {collapsedRepos.has(repoName) ? 'rotate-0' : 'rotate-90'}" 
                    fill="none" 
                    viewBox="0 0 24 24" 
                    stroke="currentColor"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                  </svg>
                </button>

                <!-- Repository Runs -->
                {#if !collapsedRepos.has(repoName)}
                  <div class="divide-y divide-[var(--sg-border)]">
                    {#each groupedRuns[repoName] as run}
                      <a 
                        href={getRunDetailHref(run.id)}
                        on:click={(e) => {
                          // Allow middle-click and Ctrl/Cmd+click to open in new tab
                          if (e.button !== 0 || e.ctrlKey || e.metaKey) {
                            return;
                          }
                          e.preventDefault();
                          navigateToRun(run.id);
                        }}
                        class="block w-full text-left p-4 md:p-6 hover:bg-[var(--sg-bg-2)] transition-colors cursor-pointer"
                      >
                        <div class="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                          <div class="flex-1">
                            <div class="mb-2">
                              <div class="flex items-start gap-2 flex-wrap">
                                <!-- Plan/Apply Visual Indicator -->
                                {#if run.run_type === 'plan'}
                                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] border border-[var(--sg-accent)] flex-shrink-0">
                                    📋 Plan
                                  </span>
                                {:else if run.run_type === 'apply'}
                                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)] border border-[var(--sg-success)] flex-shrink-0">
                                    🚀 Apply
                                  </span>
                                {:else}
                                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] border border-[var(--sg-border)] flex-shrink-0">
                                    {run.run_type}
                                  </span>
                                {/if}
                                
                                <!-- Drift Detection Indicator -->
                                {#if run.kind === 'drift'}
                                  <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-warning-bg)] text-[var(--sg-warning)] border border-[var(--sg-warning)] flex-shrink-0">
                                    🔍 Drift
                                  </span>
                                {/if}
                                
                                <!-- Path and details on separate line if needed -->
                                <div class="flex items-center gap-1 flex-wrap">
                                  <span class="text-sm text-[var(--sg-text-muted)]">{run.branch}</span>
                                  {#if run.dir}
                                    <span class="text-xs text-[var(--sg-text-dim)]">•</span>
                                    <span class="text-xs text-[var(--sg-text-dim)] font-mono break-all">{run.dir}</span>
                                  {/if}
                                  {#if run.workspace && run.workspace !== 'default'}
                                    <span class="text-xs text-[var(--sg-text-dim)]">•</span>
                                    <span class="text-xs text-[var(--sg-text-dim)]">workspace: {run.workspace}</span>
                                  {/if}
                                  {#if run.environment}
                                    <span class="text-xs text-[var(--sg-text-dim)]">•</span>
                                    <span class="text-xs text-[var(--sg-text-dim)]">env: {run.environment}</span>
                                  {/if}
                                </div>
                              </div>
                            </div>
                            <!-- Terraform summary removed for memory safety -->
                            <div class="text-xs text-[var(--sg-text-dim)]">
                              {formatDateTime(run.created_at)}
                              {#if run.user}
                                • by {run.user}
                              {/if}
                            </div>
                          </div>
                          <div class="flex items-center gap-2 self-start">
                            <span class="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium {getStateColor(run.state)}">
                              {run.state}
                            </span>
                            <svg class="w-4 h-4 text-[var(--sg-text-dim)] flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                            </svg>
                          </div>
                        </div>
                      </a>
                    {/each}
                  </div>
                {/if}
              </div>
            {/each}
          </div>

          <!-- Results Summary -->
          {#if workManifests.length > 0}
            <div class="mt-6 py-4 border-t border-[var(--sg-border)]">
              <div class="text-sm text-[var(--sg-text-dim)] text-center">
                Showing {workManifests.length} run{workManifests.length !== 1 ? 's' : ''}
              </div>
              
              <!-- Load More Button -->
              {#if hasMoreResults}
                <div class="mt-4 text-center">
                  <button
                    on:click={loadMoreRuns}
                    disabled={isLoadingMore}
                    class="inline-flex items-center px-4 py-2 border border-[var(--sg-border)] rounded-md shadow-sm text-sm font-medium text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] hover:bg-[var(--sg-bg-2)] focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-[var(--sg-accent)] disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {#if isLoadingMore}
                      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-[var(--sg-text-dim)]" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Loading more...
                    {:else}
                      Load More
                    {/if}
                  </button>
                </div>
              {/if}
            </div>
          {/if}
        {/if}
      </div>
      {/if}
  </PageLayout>
