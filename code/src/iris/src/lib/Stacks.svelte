<script lang="ts">
  import PageLayout from './components/layout/PageLayout.svelte';
  import StacksPRsView from './components/stacks/StacksPRsView.svelte';
  import StacksRepositoryView from './components/stacks/StacksRepositoryView.svelte';
  import StacksDashboardView from './components/stacks/StacksDashboardView.svelte';
  import StacksTimelineView from './components/stacks/StacksTimelineView.svelte';
  import type { StackWithRuns, PRWithStacks, RepositoryWithStacks, DashboardMetrics, Dirspace, TimelineEvent } from './types';
  import { loadRecentStacksData, groupStacksByPR, groupStacksByRepositoryAndStack, computeDashboardMetrics, generateTimelineData } from './utils/stacksDataLoader';
  import { selectedInstallation } from './stores';
  import { LoadingSpinner } from './components';
  import { onMount } from 'svelte';

  // Route params (provided by router, may be unused)
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  export let params: { installationId?: string } = {};

  // Tab management
  type StacksTab = 'prs' | 'repos' | 'dashboard' | 'timeline';
  let activeTab: StacksTab = 'dashboard';

  // Parse URL hash for initial tab
  const urlParams = new URLSearchParams(window.location.hash.split('?')[1] || '');
  const tabParam = urlParams.get('tab');
  if (tabParam === 'prs' || tabParam === 'repos' || tabParam === 'dashboard' || tabParam === 'timeline') {
    activeTab = tabParam;
  }

  // Update URL when tab changes
  function setActiveTab(tab: StacksTab): void {
    activeTab = tab;
    const currentHash = window.location.hash.split('?')[0];
    const newUrl = `${currentHash}?tab=${tab}`;
    window.history.replaceState({}, '', newUrl);
  }

  // Data state (loaded once, transformed for different views)
  let stacksWithRuns: StackWithRuns[] = [];
  let prsWithStacks: PRWithStacks[] = [];
  let repositoriesWithStacks: RepositoryWithStacks[] = [];
  let dirspaces: Dirspace[] = [];
  let dashboardMetrics: DashboardMetrics | null = null;
  let timelineEvents: TimelineEvent[] = [];
  let isLoading: boolean = true;
  let error: string | null = null;
  let loadErrors: Array<{ prNumber: number; error: string }> = [];

  // Shared filter state (affects all views)
  let searchQuery: string = '';
  let repoFilter: string = '';
  let timeRange: number = 7; // days

  // UI state
  let uniqueRepos: string[] = [];

  /**
   * Loads stacks data from API
   */
  async function loadStacks(): Promise<void> {
    if (!$selectedInstallation) {
      error = 'No installation selected';
      isLoading = false;
      return;
    }

    isLoading = true;
    error = null;
    loadErrors = [];

    try {
      const result = await loadRecentStacksData($selectedInstallation.id, timeRange);

      stacksWithRuns = result.stacksWithRuns;
      dirspaces = result.dirspaces;
      loadErrors = result.errors;

      // Group stacks by PR (for PRs view)
      prsWithStacks = groupStacksByPR(stacksWithRuns);

      // Group stacks by repository, then by stack (for combined Repositories + Stacks view)
      repositoriesWithStacks = groupStacksByRepositoryAndStack(stacksWithRuns);

      // Compute dashboard metrics (for Dashboard view)
      dashboardMetrics = computeDashboardMetrics(stacksWithRuns, prsWithStacks, dirspaces, timeRange);

      // Generate timeline events (for Timeline view)
      timelineEvents = generateTimelineData(dirspaces, stacksWithRuns);

      // Extract unique repositories for filter dropdown
      uniqueRepos = [...new Set(prsWithStacks.map(pr => pr.repo))].sort();
    } catch (err) {
      error = err instanceof Error ? err.message : 'Failed to load stacks';
      console.error('Error loading stacks:', err);
    } finally {
      isLoading = false;
    }
  }

  /**
   * Changes time range and reloads
   */
  function changeTimeRange(days: number): void {
    timeRange = days;
    loadStacks();
  }

  /**
   * Resets shared filters
   */
  function resetFilters(): void {
    searchQuery = '';
    repoFilter = '';
  }

  // Reactive: Load stacks when installation changes
  $: if ($selectedInstallation) {
    loadStacks();
  }

  // Load on mount
  onMount(() => {
    loadStacks();
  });
</script>

<PageLayout activeItem="stacks" title="Stacks" subtitle="Infrastructure stacks across active pull requests">
  <div class="space-y-4">
    <!-- Shared Filters & Controls -->
    <div class="bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)] p-4">
      <!-- Top row: Time range and Refresh -->
      <div class="flex items-center gap-3 mb-3">
        <span class="text-sm font-medium text-[var(--sg-text-muted)]">Time:</span>
        <div class="inline-flex rounded-md shadow-sm" role="group">
          <button
            on:click={() => changeTimeRange(7)}
            class="px-3 py-1.5 text-sm font-medium rounded-l-md border {timeRange === 7
              ? 'bg-[var(--sg-accent-button)] text-white border-[var(--sg-accent)]'
              : 'bg-[var(--sg-bg-1)] text-[var(--sg-text-muted)] border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)]'}"
            aria-label="Last 7 days"
            aria-pressed={timeRange === 7}
          >
            7d
          </button>
          <button
            on:click={() => changeTimeRange(14)}
            class="px-3 py-1.5 text-sm font-medium border-t border-b {timeRange === 14
              ? 'bg-[var(--sg-accent-button)] text-white border-[var(--sg-accent)]'
              : 'bg-[var(--sg-bg-1)] text-[var(--sg-text-muted)] border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)]'}"
            aria-label="Last 14 days"
            aria-pressed={timeRange === 14}
          >
            14d
          </button>
          <button
            on:click={() => changeTimeRange(30)}
            class="px-3 py-1.5 text-sm font-medium rounded-r-md border {timeRange === 30
              ? 'bg-[var(--sg-accent-button)] text-white border-[var(--sg-accent)]'
              : 'bg-[var(--sg-bg-1)] text-[var(--sg-text-muted)] border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)]'}"
            aria-label="Last 30 days"
            aria-pressed={timeRange === 30}
          >
            30d
          </button>
        </div>
        <button
          on:click={loadStacks}
          class="ml-auto inline-flex items-center px-3 py-1.5 border border-[var(--sg-border)] shadow-sm text-sm font-medium rounded-md text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] hover:bg-[var(--sg-bg-2)] transition-colors"
          disabled={isLoading}
          aria-label="Refresh stacks"
        >
          <svg class="w-4 h-4 mr-1.5 {isLoading ? 'animate-spin' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          Refresh
        </button>
      </div>

      <!-- Filters row -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <!-- Search -->
        <div>
          <label for="search" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">
            Search
          </label>
          <input
            id="search"
            type="text"
            bind:value={searchQuery}
            placeholder="PR title, number, or stack..."
            class="w-full px-3 py-1.5 text-sm border border-[var(--sg-border)] rounded-md bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder-[var(--sg-text-dim)] focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-transparent"
          />
        </div>

        <!-- Repository filter -->
        <div>
          <label for="repo-filter" class="block text-xs font-medium text-[var(--sg-text-muted)] mb-1">
            Repository
          </label>
          <select
            id="repo-filter"
            bind:value={repoFilter}
            class="w-full px-3 py-1.5 text-sm border border-[var(--sg-border)] rounded-md bg-[var(--sg-bg-1)] text-[var(--sg-text)] focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-transparent"
          >
            <option value="">All repositories</option>
            {#each uniqueRepos as repo}
              <option value={repo}>{repo}</option>
            {/each}
          </select>
        </div>
      </div>

      <!-- Reset button -->
      {#if searchQuery || repoFilter}
        <div class="mt-3">
          <button
            on:click={resetFilters}
            class="text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent)] font-medium transition-colors"
          >
            Reset Filters
          </button>
        </div>
      {/if}
    </div>

    <!-- Tab Navigation -->
    <div class="border-b border-[var(--sg-border)]">
      <div class="-mb-px flex space-x-8" role="tablist" aria-label="Tabs">
        <button
          on:click={() => setActiveTab('dashboard')}
          class="py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-200 {activeTab === 'dashboard'
            ? 'border-[var(--sg-accent)] text-[var(--sg-accent)]'
            : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:border-[var(--sg-border)]'}"
          role="tab"
          aria-selected={activeTab === 'dashboard'}
          aria-controls="dashboard-panel"
        >
          Dashboard
        </button>
        <button
          on:click={() => setActiveTab('prs')}
          class="py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-200 {activeTab === 'prs'
            ? 'border-[var(--sg-accent)] text-[var(--sg-accent)]'
            : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:border-[var(--sg-border)]'}"
          role="tab"
          aria-selected={activeTab === 'prs'}
          aria-controls="prs-panel"
        >
          Pull Requests
        </button>
        <button
          on:click={() => setActiveTab('repos')}
          class="py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-200 {activeTab === 'repos'
            ? 'border-[var(--sg-accent)] text-[var(--sg-accent)]'
            : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:border-[var(--sg-border)]'}"
          role="tab"
          aria-selected={activeTab === 'repos'}
          aria-controls="repos-panel"
        >
          Repositories
        </button>
        <button
          on:click={() => setActiveTab('timeline')}
          class="py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-200 {activeTab === 'timeline'
            ? 'border-[var(--sg-accent)] text-[var(--sg-accent)]'
            : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:border-[var(--sg-border)]'}"
          role="tab"
          aria-selected={activeTab === 'timeline'}
          aria-controls="timeline-panel"
        >
          Timeline
        </button>
      </div>
    </div>

    <!-- Tab Panels -->
    <div class="space-y-4">
      {#if activeTab === 'dashboard'}
        <div role="tabpanel" id="dashboard-panel" aria-labelledby="dashboard-tab">
          {#if dashboardMetrics}
            <StacksDashboardView
              metrics={dashboardMetrics}
              {prsWithStacks}
              {isLoading}
              {error}
              onNavigateToPRs={() => setActiveTab('prs')}
            />
          {:else if isLoading}
            <div class="text-center py-12">
              <LoadingSpinner size="xl" centered={false} />
              <p class="mt-4 text-[var(--sg-text-dim)]">Loading dashboard data...</p>
            </div>
          {:else if error}
            <div class="rounded-md bg-[var(--sg-error-bg)] p-4 border border-[var(--sg-error)]" role="alert">
              <div class="flex">
                <div class="ml-3">
                  <h3 class="text-sm font-medium text-[var(--sg-error)]">Error loading dashboard</h3>
                  <div class="mt-2 text-sm text-[var(--sg-error)]">{error}</div>
                </div>
              </div>
            </div>
          {:else}
            <div class="text-center py-12">
              <p class="text-[var(--sg-text-dim)]">No dashboard data available</p>
            </div>
          {/if}
        </div>
      {:else if activeTab === 'prs'}
        <div role="tabpanel" id="prs-panel" aria-labelledby="prs-tab">
          <StacksPRsView
            {prsWithStacks}
            {isLoading}
            {error}
            {loadErrors}
            {searchQuery}
            {repoFilter}
            {uniqueRepos}
            {timeRange}
            onRefresh={loadStacks}
          />
        </div>
      {:else if activeTab === 'repos'}
        <div role="tabpanel" id="repos-panel" aria-labelledby="repos-tab">
          <StacksRepositoryView
            {repositoriesWithStacks}
            {isLoading}
            {error}
            {loadErrors}
            {searchQuery}
            {timeRange}
            onRefresh={loadStacks}
          />
        </div>
      {:else if activeTab === 'timeline'}
        <div role="tabpanel" id="timeline-panel" aria-labelledby="timeline-tab">
          <StacksTimelineView
            {timelineEvents}
            {isLoading}
            {error}
            {searchQuery}
            {timeRange}
            onRefresh={loadStacks}
          />
        </div>
      {/if}
    </div>
  </div>
</PageLayout>
