<script lang="ts">
  import type { Dirspace, Repository } from './types';
  // Auth handled by PageLayout
  import { api } from './api';
  import { selectedInstallation, installationsLoading, currentVCSProvider } from './stores';
  import { repositoryService } from './services/repository-service';
  import PageLayout from './components/layout/PageLayout.svelte';
  import { navigateToWorkspace } from './utils/navigation';
  import LoadingSpinner from './components/ui/LoadingSpinner.svelte';
  import ErrorMessage from './components/ui/ErrorMessage.svelte';
  import EmptyState from './components/ui/EmptyState.svelte';
  import Card from './components/ui/Card.svelte';
  import ClickableCard from './components/ui/ClickableCard.svelte';
  import { VCS_PROVIDERS } from './vcs/providers';
  import { EXTERNAL_URLS } from './constants';

  // Get current VCS provider terminology
  $: currentProvider = $currentVCSProvider || 'github';
  $: terminology = VCS_PROVIDERS[currentProvider]?.terminology || VCS_PROVIDERS.github.terminology;
  
  let repositories: Repository[] = [];
  let filteredRepositories: Repository[] = [];
  let isLoadingRepositories: boolean = false;
  let error: string | null = null;
  
  // Pagination state
  let currentPage: number = 1;
  let itemsPerPage: number = 20;
  let totalPages: number = 1;
  
  // Search state
  let searchQuery: string = '';

  // Repository workspaces - lazy loaded per repo
  let repoWorkspaces: Record<string, Dirspace[]> = {};
  let loadingRepos: Set<string> = new Set(); // Track which repos are currently loading
  let loadedRepos: Set<string> = new Set(); // Track which repos have been loaded
  let repoErrors: Record<string, string> = {}; // Track loading errors per repo
  let collapsedRepos: Set<string> = new Set(); // Track collapsed state
  
  // Note: Pagination removed because dirspaces API returns operations, not unique workspaces
  // We load all dirspaces at once and deduplicate to show unique workspaces
  
  // Summary stats
  let totalWorkspaceCount: number = 0;
  
  // Update filtered repositories when search query changes
  $: {
    if (searchQuery.trim() === '') {
      filteredRepositories = repositories;
    } else {
      const query = searchQuery.toLowerCase();
      filteredRepositories = repositories.filter(repo => 
        repo.name.toLowerCase().includes(query)
      );
    }
    // Reset to first page when search changes
    currentPage = 1;
  }
  
  // Calculate pagination
  $: totalPages = Math.ceil(filteredRepositories.length / itemsPerPage);
  $: paginatedRepositories = filteredRepositories.slice(
    (currentPage - 1) * itemsPerPage,
    currentPage * itemsPerPage
  );
  
  // Reset page if it exceeds total pages
  $: if (currentPage > totalPages && totalPages > 0) {
    currentPage = 1;
  }
  
  const DIRSPACES_PER_REQUEST = 1000; // Load many dirspaces to find all unique workspaces

  // Load data when installation changes
  let lastInstallationId: string | null = null;
  $: if ($selectedInstallation && $selectedInstallation.id !== lastInstallationId) {
    lastInstallationId = $selectedInstallation.id;
    // Reset state
    repoWorkspaces = {};
    loadedRepos = new Set();
    loadingRepos = new Set();
    repoErrors = {};
    collapsedRepos = new Set();
    totalWorkspaceCount = 0;
    
    loadRepositories();
  }
  
  async function loadRepositories(): Promise<void> {
    if (!$selectedInstallation) return;
    
    repositories = [];
    isLoadingRepositories = true;
    error = null;
    
    try {
      const result = await repositoryService.loadRepositories($selectedInstallation);
      repositories = result.repositories;
      
      if (result.error) {
        error = result.error;
      } else {
        // Initialize all repos as collapsed by default
        repositories.forEach(repo => {
          collapsedRepos.add(repo.name);
        });
        collapsedRepos = new Set(collapsedRepos); // Trigger reactivity
      }
      
    } catch (err) {
      console.error('Error loading repositories:', err);
      error = err instanceof Error ? err.message : 'Failed to load repositories';
      repositories = [];
    } finally {
      isLoadingRepositories = false;
    }
  }

  async function loadWorkspacesForRepo(repoName: string): Promise<void> {
    if (!$selectedInstallation) return;
    if (loadedRepos.has(repoName) || loadingRepos.has(repoName)) return;
    
    // Mark as loading
    loadingRepos.add(repoName);
    loadingRepos = new Set(loadingRepos);
    
    try {
      // Load a large number of dirspaces to find all unique workspaces
      // Since dirspaces are operations (not workspace definitions), we need to
      // load many to ensure we capture all unique workspace combinations
      const response = await api.getInstallationDirspaces($selectedInstallation.id, {
        q: `repo:${repoName}`,
        limit: DIRSPACES_PER_REQUEST,
        d: 'desc' // Sort by descending to get newest first
      });
      
      if (response && response.dirspaces && response.dirspaces.length > 0) {
        // Deduplicate workspaces by dir:workspace key
        const uniqueWorkspacesMap = new Map<string, Dirspace>();
        
        response.dirspaces.forEach((dirspace: Dirspace) => {
          const workspaceKey = `${dirspace.dir}:${dirspace.workspace}`;
          
          // Keep the most recent dirspace for each unique workspace
          const existing = uniqueWorkspacesMap.get(workspaceKey);
          if (!existing || (dirspace.completed_at && existing.completed_at && 
              new Date(dirspace.completed_at) > new Date(existing.completed_at))) {
            uniqueWorkspacesMap.set(workspaceKey, dirspace);
          }
        });
        
        // Convert map to array
        const uniqueWorkspaces = Array.from(uniqueWorkspacesMap.values());
        
        // Sort by most recently used (already sorted by API, but ensure consistency)
        uniqueWorkspaces.sort((a, b) => {
          const dateA = a.completed_at ? new Date(a.completed_at).getTime() : 0;
          const dateB = b.completed_at ? new Date(b.completed_at).getTime() : 0;
          return dateB - dateA;
        });
        
        repoWorkspaces[repoName] = uniqueWorkspaces;
        
        // Update total count
        totalWorkspaceCount += uniqueWorkspaces.length;
        
      } else {
        repoWorkspaces[repoName] = [];
      }
      
      // Mark as loaded
      loadedRepos.add(repoName);
      loadedRepos = new Set(loadedRepos);
      
    } catch (err) {
      console.error(`Failed to load workspaces for ${repoName}:`, err);
      repoErrors[repoName] = err instanceof Error ? err.message : 'Failed to load workspaces';
      repoWorkspaces[repoName] = [];
    } finally {
      // Remove from loading
      loadingRepos.delete(repoName);
      loadingRepos = new Set(loadingRepos);
    }
    
    // Trigger reactivity
    repoWorkspaces = { ...repoWorkspaces };
  }

  async function toggleRepoCollapse(repoName: string): Promise<void> {
    const newCollapsed = new Set(collapsedRepos);
    if (newCollapsed.has(repoName)) {
      // Expanding - load workspaces if not already loaded
      newCollapsed.delete(repoName);
      if (!loadedRepos.has(repoName) && !loadingRepos.has(repoName)) {
        await loadWorkspacesForRepo(repoName);
      }
    } else {
      // Collapsing
      newCollapsed.add(repoName);
    }
    collapsedRepos = newCollapsed;
  }
  
  function formatDate(dateString: string): string {
    return new Date(dateString).toLocaleString();
  }
  
  function getStateColor(state: string): string {
    switch (state) {
      case 'success':
        return 'bg-[var(--sg-success-bg)] text-[var(--sg-success)]';
      case 'failure':
        return 'bg-[var(--sg-error-bg)] text-[var(--sg-error)]';
      case 'running':
        return 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)]';
      case 'queued':
        return 'bg-[var(--sg-warning-bg)] text-[var(--sg-warning)]';
      case 'aborted':
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)]';
      default:
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)]';
    }
  }
  
  function getStateIcon(state: string): string {
    switch (state) {
      case 'success':
        return '✅';
      case 'failure':
        return '❌';
      case 'running':
        return '🔄';
      case 'queued':
        return '⏳';
      case 'aborted':
        return '⚠️';
      default:
        return '❓';
    }
  }
  
  function getRunTypeLabel(runType: string): string {
    switch (runType) {
      case 'plan':
        return '📋 Plan';
      case 'apply':
        return '🚀 Apply';
      case 'index':
        return '📑 Index';
      case 'build-config':
        return '🔧 Build Config';
      case 'build-tree':
        return '🌳 Build Tree';
      default:
        return runType;
    }
  }

  // Get all workspaces from loaded repos
  $: allWorkspaces = Object.values(repoWorkspaces).flat();

  // Calculate summary statistics (only from loaded workspaces)
  $: totalRepositories = repositories.length;
  $: successfulWorkspaces = allWorkspaces.filter(ws => ws.state === 'success').length;
  $: failedWorkspaces = allWorkspaces.filter(ws => ws.state === 'failure').length;
  
  function goToPage(page: number): void {
    if (page >= 1 && page <= totalPages) {
      currentPage = page;
      // Scroll to top of repository list
      document.getElementById('repository-list')?.scrollIntoView({ behavior: 'smooth' });
    }
  }
  
</script>

<PageLayout 
  activeItem="workspaces" 
  title="Workspaces"
  subtitle="Manage Terraform directories and workspace combinations across your repositories"
>
  <!-- Summary Cards -->
  <div class="grid grid-cols-2 md:grid-cols-4 gap-3 md:gap-6 mb-6 md:mb-8">
    <Card padding="md" class="text-center">
      <div class="text-2xl md:text-3xl font-bold text-[var(--sg-text)]">{totalWorkspaceCount}</div>
      <div class="text-xs md:text-sm text-[var(--sg-text-muted)] mt-1">Workspaces Loaded</div>
    </Card>
    <Card padding="md" class="text-center">
      <div class="text-2xl md:text-3xl font-bold text-[var(--sg-text)]">{totalRepositories}</div>
      <div class="text-xs md:text-sm text-[var(--sg-text-muted)] mt-1">Repositories</div>
    </Card>
    <Card padding="md" class="text-center">
      <div class="text-2xl md:text-3xl font-bold text-[var(--sg-success)]">{successfulWorkspaces}</div>
      <div class="text-xs md:text-sm text-[var(--sg-text-muted)] mt-1">Successful</div>
    </Card>
    <Card padding="md" class="text-center">
      <div class="text-2xl md:text-3xl font-bold text-[var(--sg-error)]">{failedWorkspaces}</div>
      <div class="text-xs md:text-sm text-[var(--sg-text-muted)] mt-1">Failed</div>
    </Card>
  </div>

  <!-- Search Bar and Controls -->
  {#if repositories.length > 0}
    <div class="mb-6 space-y-4">
      <!-- Search Input -->
      <div class="relative">
        <input
          type="text"
          bind:value={searchQuery}
          placeholder="Search repositories..."
          class="w-full px-4 py-2 pl-10 pr-4 text-[var(--sg-text)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-lg focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-transparent transition-colors"
          aria-label="Search repositories"
        />
        <div class="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none">
          <svg class="w-5 h-5 text-[var(--sg-text-dim)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
          </svg>
        </div>
        {#if searchQuery}
          <button
            on:click={() => searchQuery = ''}
            class="absolute inset-y-0 right-0 flex items-center pr-3 text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)]"
            aria-label="Clear search"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        {/if}
      </div>
      
      <!-- Results Info and Pagination Info -->
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2 text-sm text-[var(--sg-text-muted)]">
        <div>
          {#if searchQuery}
            <p>Found {filteredRepositories.length} repositor{filteredRepositories.length === 1 ? 'y' : 'ies'} matching "{searchQuery}"</p>
          {:else}
            <p>Showing {paginatedRepositories.length} of {repositories.length} repositor{repositories.length === 1 ? 'y' : 'ies'}</p>
          {/if}
        </div>
        {#if totalPages > 1}
          <div>
            Page {currentPage} of {totalPages}
          </div>
        {/if}
      </div>
    </div>
  {/if}
  
  <!-- Lazy loading info -->
  {#if paginatedRepositories.length > 0 && totalWorkspaceCount === 0 && !isLoadingRepositories}
    <div class="mb-6 text-sm text-[var(--sg-text-muted)] text-center">
      <p>Click on a repository below to load its workspaces</p>
    </div>
  {/if}

  <!-- Content -->
  {#if $installationsLoading}
    <!-- Loading installations -->
    <div class="flex flex-col items-center py-12">
      <LoadingSpinner size="lg" />
      <div class="mt-4 text-center">
        <p class="text-[var(--sg-text-muted)]">Loading installations...</p>
      </div>
    </div>
  {:else if !$selectedInstallation}
    <!-- Demo Mode Message -->
    <Card padding="lg" class="border-[var(--sg-accent)] bg-[var(--sg-accent-bg)]">
      <div class="text-center">
        <div class="flex justify-center mb-4">
          <svg class="w-16 h-16 text-[var(--sg-accent)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4" />
          </svg>
        </div>
        <h3 class="text-xl font-semibold text-[var(--sg-accent)] mb-2">Demo Mode - Workspaces</h3>
        <p class="text-[var(--sg-accent)] mb-6">
          You're viewing the workspaces page in demo mode. Once you connect a {VCS_PROVIDERS[currentProvider].displayName} {terminology.organization.toLowerCase()}, you'll see your actual Terraform workspaces and their status.
        </p>
        
        <div class="grid gap-4 mb-6">
          <div class="text-sm text-[var(--sg-accent)] bg-[var(--sg-bg-1)] rounded-lg p-4 border border-[var(--sg-accent)]">
            <div class="font-semibold mb-2">What you'll see here:</div>
            <ul class="text-left space-y-1">
              <li>• All your Terraform workspaces across repositories</li>
              <li>• Workspace status and last run information</li>
              <li>• Quick access to workspace-specific operations</li>
              <li>• Environment-based organization of your infrastructure</li>
              <li>• Real-time status tracking for all workspaces</li>
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
  {:else if isLoadingRepositories}
    <div class="flex flex-col items-center py-12">
      <LoadingSpinner size="lg" />
      <div class="mt-4 text-center">
        <p class="text-[var(--sg-text-muted)]">Loading repositories...</p>
      </div>
    </div>
  {:else if error}
    <ErrorMessage type="error" message={error} />
  {:else if repositories.length === 0 && !searchQuery}
    <Card padding="lg">
      <EmptyState icon="mdi:package-variant" title="No Repositories Found" description="No repositories are connected to this installation yet.">
        <p class="mt-2 text-sm text-[var(--sg-text-dim)]">
          Need help? <a href={EXTERNAL_URLS.SLACK} target="_blank" rel="noopener noreferrer" class="text-[var(--sg-accent)] hover:underline">Join our Slack community</a>
        </p>
      </EmptyState>
    </Card>
  {:else if filteredRepositories.length === 0 && searchQuery}
    <Card padding="lg">
      <EmptyState icon="mdi:magnify" title="No Repositories Found" description={`No repositories match your search "${searchQuery}".`}>
        <button
          on:click={() => searchQuery = ''}
          class="mt-4 px-4 py-2 bg-[var(--sg-accent-button)] text-white rounded-lg hover:bg-[var(--sg-accent-button-hover)] transition-colors"
        >
          Clear Search
        </button>
      </EmptyState>
    </Card>
  {:else}
    <!-- Repository Listings -->
    <div id="repository-list" class="space-y-6">
      {#each paginatedRepositories as repository}
        {@const repoName = repository.name}
        {@const workspaces = repoWorkspaces[repoName] || []}
        {@const isLoading = loadingRepos.has(repoName)}
        {@const hasError = repoErrors[repoName]}
        
        <Card padding="none" class="overflow-hidden">
          <!-- Repository Header -->
          <button
            on:click={() => toggleRepoCollapse(repoName)}
            class="w-full px-4 md:px-6 py-3 md:py-4 bg-[var(--sg-bg-2)] border-b border-[var(--sg-border)] flex items-center justify-between hover:bg-[var(--sg-bg-2)] transition-colors"
          >
            <div class="flex items-center space-x-2 md:space-x-3">
              <svg class="w-5 h-5 transition-transform {collapsedRepos.has(repoName) ? '' : 'rotate-90'}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
              </svg>
              <div class="text-left min-w-0 flex-1">
                <h3 class="text-base md:text-lg font-semibold text-[var(--sg-text)] truncate">{repoName}</h3>
                <p class="text-xs md:text-sm text-[var(--sg-text-muted)]">
                  {#if loadedRepos.has(repoName)}
                    {workspaces.length} workspace{workspaces.length !== 1 ? 's' : ''}
                  {:else if isLoading}
                    Loading...
                  {:else}
                    Click to load workspaces
                  {/if}
                </p>
              </div>
            </div>
            <div class="flex items-center space-x-1 md:space-x-2 flex-shrink-0">
              {#if isLoading}
                <LoadingSpinner size="sm" />
              {:else if loadedRepos.has(repoName) && workspaces.length > 0}
                <!-- Status summary for this repo -->
                <span class="text-xs px-1.5 md:px-2 py-0.5 md:py-1 bg-[var(--sg-success-bg)] text-[var(--sg-success)] rounded-full">
                  {workspaces.filter(ws => ws.state === 'success').length} ✅
                </span>
                <span class="text-xs px-1.5 md:px-2 py-0.5 md:py-1 bg-[var(--sg-error-bg)] text-[var(--sg-error)] rounded-full">
                  {workspaces.filter(ws => ws.state === 'failure').length} ❌
                </span>
              {/if}
            </div>
          </button>
          
          <!-- Workspace List -->
          {#if !collapsedRepos.has(repoName)}
            {#if hasError}
              <div class="p-4 bg-[var(--sg-error-bg)]">
                <ErrorMessage type="error" message={`Failed to load workspaces: ${hasError}`} />
              </div>
            {:else if isLoading}
              <div class="p-8 text-center">
                <LoadingSpinner size="md" />
                <p class="text-sm text-[var(--sg-text-muted)] mt-2">Loading workspaces...</p>
              </div>
            {:else if !loadedRepos.has(repoName)}
              <div class="p-8 text-center text-[var(--sg-text-dim)]">
                <p class="text-sm">Click the repository header to load workspaces</p>
              </div>
            {:else if workspaces.length === 0}
              <div class="p-8">
                <EmptyState title="No workspaces found" description="No workspaces found for this repository" />
              </div>
            {:else}
              <div class="divide-y divide-[var(--sg-divider)]">
                {#each workspaces as workspace}
                <button
                  on:click={() => navigateToWorkspace(workspace.repo, workspace.dir, workspace.workspace)}
                  class="w-full p-4 md:p-6 text-left hover:bg-[var(--sg-bg-2)] transition-colors cursor-pointer"
                >
                  <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-3">
                    <div class="flex-1 min-w-0">
                      <div class="flex items-center gap-2 mb-2">
                        <h4 class="text-base md:text-lg font-medium text-[var(--sg-text)] hover:text-[var(--sg-accent)] transition-colors truncate" title={workspace.dir}>
                          📁 {workspace.dir}
                        </h4>
                        <div class="flex items-center gap-2 flex-shrink-0">
                          <span class="text-xs md:text-sm px-2 py-0.5 md:py-1 bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] rounded-full font-mono whitespace-nowrap" title="Workspace: {workspace.workspace}">
                            {workspace.workspace}
                          </span>
                          <span class={`text-xs px-2 py-0.5 md:py-1 rounded-full font-medium whitespace-nowrap ${getStateColor(workspace.state)}`} title="Status: {workspace.state}">
                            {getStateIcon(workspace.state)} {workspace.state}
                          </span>
                        </div>
                      </div>
                      
                      <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 md:gap-4 text-xs md:text-sm text-[var(--sg-text-muted)]">
                        <div class="truncate">
                          <span class="font-medium">{$currentVCSProvider === 'gitlab' ? 'GitLab' : 'GitHub'} Environment:</span>
                          <span class="ml-1">{workspace.environment || 'default'}</span>
                        </div>
                        <div class="truncate">
                          <span class="font-medium">Last Run:</span>
                          <span class="ml-1">{getRunTypeLabel(workspace.run_type)}</span>
                        </div>
                        <div class="truncate">
                          <span class="font-medium">Updated:</span>
                          <span class="ml-1">{formatDate(workspace.created_at)}</span>
                        </div>
                      </div>
                      
                      {#if workspace.user}
                        <div class="mt-2 text-xs md:text-sm text-[var(--sg-text-muted)] truncate">
                          <span class="font-medium">Last User:</span>
                          <span class="ml-1">{workspace.user}</span>
                        </div>
                      {/if}
                      
                      {#if workspace.branch && workspace.branch !== workspace.base_branch}
                        <div class="mt-2 text-xs md:text-sm text-[var(--sg-text-muted)] truncate">
                          <span class="font-medium">Branch:</span>
                          <span class="ml-1 font-mono">{workspace.branch}</span>
                          <span class="mx-1 md:mx-2">→</span>
                          <span class="font-mono">{workspace.base_branch}</span>
                        </div>
                      {/if}
                    </div>
                    
                    <div class="flex items-center space-x-2 flex-shrink-0">
                      <span class="hidden md:inline text-sm text-[var(--sg-text-dim)]">Click for details →</span>
                      <svg class="w-4 h-4 text-[var(--sg-text-dim)] md:hidden" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                      </svg>
                    </div>
                  </div>
                </button>
                {/each}
              </div>
              
            {/if}
          {/if}
        </Card>
      {/each}
    </div>
    
    <!-- Pagination Controls -->
    {#if totalPages > 1}
      <div class="mt-8 flex flex-col sm:flex-row justify-center items-center gap-4">
        <nav class="flex items-center space-x-2" aria-label="Pagination">
          <!-- Previous Button -->
          <button
            on:click={() => goToPage(currentPage - 1)}
            disabled={currentPage === 1}
            class="px-3 py-2 text-sm font-medium text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-lg hover:bg-[var(--sg-bg-2)] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            aria-label="Previous page"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
            </svg>
          </button>
          
          <!-- Page Numbers -->
          {#if totalPages <= 7}
            {#each Array(totalPages) as _, i}
              <button
                on:click={() => goToPage(i + 1)}
                class="px-3 py-2 text-sm font-medium rounded-lg transition-colors {
                  currentPage === i + 1
                    ? 'bg-[var(--sg-accent-button)] text-white'
                    : 'text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)]'
                }"
                aria-label="Go to page {i + 1}"
                aria-current={currentPage === i + 1 ? 'page' : undefined}
              >
                {i + 1}
              </button>
            {/each}
          {:else}
            <!-- Smart pagination for many pages -->
            {#if currentPage > 3}
              <button
                on:click={() => goToPage(1)}
                class="px-3 py-2 text-sm font-medium text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-lg hover:bg-[var(--sg-bg-2)] transition-colors"
                aria-label="Go to page 1"
              >
                1
              </button>
              {#if currentPage > 4}
                <span class="px-2 text-[var(--sg-text-dim)]">...</span>
              {/if}
            {/if}
            
            {#each Array(5) as _, i}
              {@const pageNum = currentPage - 2 + i}
              {#if pageNum > 0 && pageNum <= totalPages}
                <button
                  on:click={() => goToPage(pageNum)}
                  class="px-3 py-2 text-sm font-medium rounded-lg transition-colors {
                    currentPage === pageNum
                      ? 'bg-[var(--sg-accent-button)] text-white'
                      : 'text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)]'
                  }"
                  aria-label="Go to page {pageNum}"
                  aria-current={currentPage === pageNum ? 'page' : undefined}
                >
                  {pageNum}
                </button>
              {/if}
            {/each}
            
            {#if currentPage < totalPages - 2}
              {#if currentPage < totalPages - 3}
                <span class="px-2 text-[var(--sg-text-dim)]">...</span>
              {/if}
              <button
                on:click={() => goToPage(totalPages)}
                class="px-3 py-2 text-sm font-medium text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-lg hover:bg-[var(--sg-bg-2)] transition-colors"
                aria-label="Go to page {totalPages}"
              >
                {totalPages}
              </button>
            {/if}
          {/if}
          
          <!-- Next Button -->
          <button
            on:click={() => goToPage(currentPage + 1)}
            disabled={currentPage === totalPages}
            class="px-3 py-2 text-sm font-medium text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-lg hover:bg-[var(--sg-bg-2)] disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            aria-label="Next page"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
            </svg>
          </button>
        </nav>
        
        <!-- Items per page selector -->
        <div class="flex items-center gap-2 text-sm">
          <label for="items-per-page" class="text-[var(--sg-text-muted)]">Show:</label>
          <select
            id="items-per-page"
            bind:value={itemsPerPage}
            on:change={() => currentPage = 1}
            class="px-3 py-1 text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] border border-[var(--sg-border)] rounded-lg focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-transparent"
          >
            <option value={10}>10</option>
            <option value={20}>20</option>
            <option value={50}>50</option>
            <option value={100}>100</option>
          </select>
          <span class="text-[var(--sg-text-muted)]">per page</span>
        </div>
      </div>
    {/if}
  {/if}
</PageLayout>
