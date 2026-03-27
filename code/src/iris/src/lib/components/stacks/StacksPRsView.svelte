<script lang="ts">
  import PRWithStacksCard from './PRWithStacksCard.svelte';
  import { LoadingSpinner } from '../index';
  import type { PRWithStacks, StackState } from '../../types';

  // Props
  export let prsWithStacks: PRWithStacks[];
  export let isLoading: boolean;
  export let error: string | null;
  export let loadErrors: Array<{ prNumber: number; error: string }>;
  export let searchQuery: string;
  export let repoFilter: string;
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  export let uniqueRepos: string[];
  export let timeRange: number;
  export let onRefresh: () => void;

  // Local state
  let stateFilter: StackState | '' = '';
  let sortBy: 'state' | 'activity' | 'repo' = 'state';
  let filteredPRs: PRWithStacks[] = [];

  /**
   * Applies current filters and sorting
   */
  function applyFiltersAndSort(): void {
    let filtered = [...prsWithStacks];

    // Filter by repository
    if (repoFilter) {
      filtered = filtered.filter(pr => pr.repo === repoFilter);
    }

    // Filter by stack state (show PRs that have ANY stack in this state)
    if (stateFilter) {
      const filterState = stateFilter as StackState;
      filtered = filtered.filter(pr => pr.stackStateCounts[filterState] > 0);
    }

    // Filter by search query (PR title, stack names)
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase().trim();
      filtered = filtered.filter(pr => {
        // Search in PR title
        if (pr.prTitle && pr.prTitle.toLowerCase().includes(query)) {
          return true;
        }

        // Search in PR number
        if (pr.prNumber.toString().includes(query)) {
          return true;
        }

        // Search in stack names
        for (const stack of pr.stacks) {
          const outerName = stack.stackOuter.name.toLowerCase();
          const innerName = stack.stackInner.name.toLowerCase();
          if (outerName.includes(query) || innerName.includes(query)) {
            return true;
          }
        }

        return false;
      });
    }

    // Sort
    switch (sortBy) {
      case 'state':
        // Sort by state severity (failed first)
        filtered.sort((a, b) => {
          const severityA = getStateSeverity(a.aggregateState);
          const severityB = getStateSeverity(b.aggregateState);
          return severityB - severityA;
        });
        break;
      case 'activity':
        // Sort by last activity (most recent first)
        filtered.sort((a, b) => {
          const dateA = new Date(a.lastActivity).getTime();
          const dateB = new Date(b.lastActivity).getTime();
          return dateB - dateA;
        });
        break;
      case 'repo':
        // Sort by repository name
        filtered.sort((a, b) => a.repo.localeCompare(b.repo));
        break;
    }

    filteredPRs = filtered;
  }

  /**
   * Gets severity score for aggregate state
   */
  function getStateSeverity(state: string): number {
    const severityMap: Record<string, number> = {
      failed: 4,
      pending: 3,
      ready: 2,
      success: 1,
      no_changes: 0,
    };
    return severityMap[state] || 0;
  }

  /**
   * Resets view-specific filters (not search/repo which are shared)
   */
  function resetFilters(): void {
    stateFilter = '';
    applyFiltersAndSort();
  }

  /**
   * Sets state filter
   */
  function setStateFilter(state: StackState | ''): void {
    stateFilter = state;
    applyFiltersAndSort();
  }

  /**
   * Computes state counts across all PRs
   */
  function computeStateCounts(prs: PRWithStacks[]): Record<StackState, number> {
    const counts: Record<StackState, number> = {
      apply_success: 0,
      apply_failed: 0,
      apply_pending: 0,
      apply_ready: 0,
      plan_pending: 0,
      plan_failed: 0,
      no_changes: 0,
    };

    for (const pr of prs) {
      // Count PRs that have at least one stack in each state
      if (pr.stackStateCounts.apply_success > 0) counts.apply_success++;
      if (pr.stackStateCounts.apply_failed > 0) counts.apply_failed++;
      if (pr.stackStateCounts.apply_pending > 0) counts.apply_pending++;
      if (pr.stackStateCounts.apply_ready > 0) counts.apply_ready++;
      if (pr.stackStateCounts.plan_pending > 0) counts.plan_pending++;
      if (pr.stackStateCounts.plan_failed > 0) counts.plan_failed++;
      if (pr.stackStateCounts.no_changes > 0) counts.no_changes++;
    }

    return counts;
  }

  // Reactive statements
  $: if (prsWithStacks || searchQuery !== undefined || repoFilter !== undefined || stateFilter !== undefined || sortBy !== undefined) {
    applyFiltersAndSort();
  }

  $: stateCounts = computeStateCounts(filteredPRs);
  $: hasActiveFilters = stateFilter !== '';
</script>

<!-- State filter buttons -->
<div class="flex items-center gap-2 flex-wrap">
  <span class="text-sm font-medium text-[var(--sg-text-muted)]">Quick Filters:</span>
  <button
    on:click={() => setStateFilter('')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === ''
      ? 'bg-[var(--sg-accent-button)] text-white'
      : 'bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)]'}"
    aria-label="Show all PRs"
    aria-pressed={stateFilter === ''}
  >
    All ({filteredPRs.length})
  </button>
  <button
    on:click={() => setStateFilter('apply_failed')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'apply_failed'
      ? 'bg-[var(--sg-error)] text-white'
      : 'bg-[var(--sg-error-bg)] text-[var(--sg-error)] hover:bg-[var(--sg-error-bg)]'}"
    aria-label="Show PRs with apply failures"
    aria-pressed={stateFilter === 'apply_failed'}
  >
    ❌ Apply Failed ({stateCounts.apply_failed})
  </button>
  <button
    on:click={() => setStateFilter('plan_failed')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'plan_failed'
      ? 'bg-[var(--sg-orange)] text-white'
      : 'bg-[var(--sg-orange-bg)] text-[var(--sg-orange)] hover:bg-[var(--sg-orange-bg)] hover:opacity-90'}"
    aria-label="Show PRs with plan failures"
    aria-pressed={stateFilter === 'plan_failed'}
  >
    ⚠️ Plan Failed ({stateCounts.plan_failed})
  </button>
  <button
    on:click={() => setStateFilter('apply_pending')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'apply_pending'
      ? 'bg-[var(--sg-purple)] text-white'
      : 'bg-[var(--sg-purple-bg)] text-[var(--sg-purple)] hover:bg-[var(--sg-purple-bg)] hover:opacity-90'}"
    aria-label="Show PRs with apply pending"
    aria-pressed={stateFilter === 'apply_pending'}
  >
    ⏳ Apply Pending ({stateCounts.apply_pending})
  </button>
  <button
    on:click={() => setStateFilter('plan_pending')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'plan_pending'
      ? 'bg-[var(--sg-pink)] text-white'
      : 'bg-[var(--sg-pink-bg)] text-[var(--sg-pink)] hover:bg-[var(--sg-pink-bg)] hover:opacity-90'}"
    aria-label="Show PRs with plan pending"
    aria-pressed={stateFilter === 'plan_pending'}
  >
    📋 Plan Pending ({stateCounts.plan_pending})
  </button>
  <button
    on:click={() => setStateFilter('apply_ready')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'apply_ready'
      ? 'bg-[var(--sg-accent-button)] text-white'
      : 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] hover:bg-[var(--sg-accent-bg)]'}"
    aria-label="Show PRs ready to apply"
    aria-pressed={stateFilter === 'apply_ready'}
  >
    ✓ Ready ({stateCounts.apply_ready})
  </button>
  <button
    on:click={() => setStateFilter('apply_success')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'apply_success'
      ? 'bg-[var(--sg-success)] text-white'
      : 'bg-[var(--sg-success-bg)] text-[var(--sg-success)] hover:bg-[var(--sg-success-bg)]'}"
    aria-label="Show successful PRs"
    aria-pressed={stateFilter === 'apply_success'}
  >
    ✅ Success ({stateCounts.apply_success})
  </button>
  <button
    on:click={() => setStateFilter('no_changes')}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'no_changes'
      ? 'bg-[var(--sg-text-dim)] text-white'
      : 'bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)]'}"
    aria-label="Show PRs with no changes"
    aria-pressed={stateFilter === 'no_changes'}
  >
    ○ No Changes ({stateCounts.no_changes})
  </button>
  {#if hasActiveFilters}
    <button
      on:click={resetFilters}
      class="px-3 py-1 rounded-md text-sm font-medium bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)] transition-colors"
    >
      Reset Quick Filters
    </button>
  {/if}
</div>

<!-- Loading state -->
{#if isLoading}
  <LoadingSpinner size="xl" />

<!-- Error state -->
{:else if error}
  <div
    class="rounded-md bg-[var(--sg-error-bg)] p-4 border border-[var(--sg-error)]"
    role="alert"
  >
    <div class="flex">
      <div class="flex-shrink-0">
        <svg class="h-5 w-5 text-[var(--sg-error)]" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
            clip-rule="evenodd"
          />
        </svg>
      </div>
      <div class="ml-3">
        <h3 class="text-sm font-medium text-[var(--sg-error)]">
          Error loading stacks
        </h3>
        <div class="mt-2 text-sm text-[var(--sg-error)]">
          {error}
        </div>
        <button
          on:click={onRefresh}
          class="mt-3 text-sm font-medium text-[var(--sg-error)] hover:text-[var(--sg-error)] underline"
        >
          Try again
        </button>
      </div>
    </div>
  </div>

<!-- Partial errors warning -->
{:else if loadErrors.length > 0}
  <div
    class="rounded-md bg-[var(--sg-warning-bg)] p-4 border border-[var(--sg-warning)]"
    role="alert"
  >
    <div class="flex">
      <div class="flex-shrink-0">
        <svg class="h-5 w-5 text-[var(--sg-warning)]" fill="currentColor" viewBox="0 0 20 20">
          <path
            fill-rule="evenodd"
            d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z"
            clip-rule="evenodd"
          />
        </svg>
      </div>
      <div class="ml-3">
        <h3 class="text-sm font-medium text-[var(--sg-warning)]">
          Some stacks could not be loaded
        </h3>
        <div class="mt-2 text-sm text-[var(--sg-warning)]">
          Failed to load stacks for {loadErrors.length} PR{loadErrors.length > 1 ? 's' : ''}.
          Showing {filteredPRs.length} PR{filteredPRs.length !== 1 ? 's' : ''} that loaded successfully.
        </div>
      </div>
    </div>
  </div>
{/if}

<!-- PRs grid -->
{#if !isLoading && !error}
  {#if filteredPRs.length > 0}
    <div class="space-y-4">
      {#each filteredPRs as prWithStacks}
        <PRWithStacksCard {prWithStacks} />
      {/each}
    </div>
  {:else}
    <!-- Empty state -->
    <div class="text-center py-12">
      <svg
        class="mx-auto h-12 w-12 text-[var(--sg-text-dim)]"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
        />
      </svg>
      <h3 class="mt-2 text-sm font-semibold text-[var(--sg-text)]">No pull requests found</h3>
      <p class="mt-1 text-sm text-[var(--sg-text-dim)]">
        {#if hasActiveFilters || searchQuery || repoFilter}
          No pull requests match your current filters. Try adjusting or resetting your filters.
        {:else}
          No active pull requests with stacks in the last {timeRange} days.
        {/if}
      </p>
    </div>
  {/if}
{/if}
