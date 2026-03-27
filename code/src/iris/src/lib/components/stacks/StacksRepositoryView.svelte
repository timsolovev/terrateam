<script lang="ts">
  import type { RepositoryWithStacks } from '../../types';
  import { EmptyState, LoadingSpinner } from '../index';

  // Props
  export let repositoriesWithStacks: RepositoryWithStacks[];
  export let isLoading: boolean;
  export let error: string | null;
  export let loadErrors: Array<{ prNumber: number; error: string }>;
  export let searchQuery: string;
  export let timeRange: number;
  export let onRefresh: () => void;

  // Local state
  let sortBy: 'state' | 'activity' | 'repo' | 'stacks' = 'state';
  let filteredRepos: RepositoryWithStacks[] = [];
  let expandedRepos: Set<string> = new Set();

  /**
   * Toggle repository expansion
   */
  function toggleRepo(repo: string): void {
    if (expandedRepos.has(repo)) {
      expandedRepos.delete(repo);
    } else {
      expandedRepos.add(repo);
    }
    expandedRepos = expandedRepos; // Trigger reactivity
  }

  /**
   * Applies current filters and sorting
   */
  function applyFiltersAndSort(): void {
    let filtered = [...repositoriesWithStacks];

    // Filter by search query (repo name, stack names, PR titles)
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase().trim();
      filtered = filtered.filter(repo => {
        // Search in repo name
        if (repo.repo.toLowerCase().includes(query)) {
          return true;
        }

        // Search in stacks
        for (const stack of repo.stacks) {
          if (stack.stackName.toLowerCase().includes(query)) {
            return true;
          }

          // Search in PRs
          for (const pr of stack.prs) {
            if (pr.prTitle && pr.prTitle.toLowerCase().includes(query)) {
              return true;
            }
            if (pr.prNumber.toString().includes(query)) {
              return true;
            }
          }

          // Search in dirspaces
          for (const ds of stack.dirspaces) {
            if (ds.dir.toLowerCase().includes(query) || ds.workspace.toLowerCase().includes(query)) {
              return true;
            }
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
      case 'stacks':
        // Sort by number of stacks (most stacks first)
        filtered.sort((a, b) => b.totalStacks - a.totalStacks);
        break;
    }

    filteredRepos = filtered;
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
   * Gets badge classes for state
   */
  function getStateBadgeClasses(state: string): string {
    switch (state) {
      case 'success':
      case 'apply_success':
        return 'bg-[var(--sg-success-bg)] text-[var(--sg-success)]';
      case 'failed':
      case 'apply_failed':
      case 'plan_failed':
        return 'bg-[var(--sg-error-bg)] text-[var(--sg-error)]';
      case 'pending':
      case 'apply_pending':
      case 'plan_pending':
        return 'bg-[var(--sg-purple-bg)] text-[var(--sg-purple)]';
      case 'ready':
      case 'apply_ready':
        return 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)]';
      case 'no_changes':
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)]';
      default:
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)]';
    }
  }

  /**
   * Formats state name for display
   */
  function formatStateName(state: string): string {
    return state.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  }

  // Reactive statements
  $: if (repositoriesWithStacks || searchQuery !== undefined || sortBy !== undefined) {
    applyFiltersAndSort();
  }
</script>

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
          Error loading repositories
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
          Showing {filteredRepos.length} {filteredRepos.length === 1 ? 'repository' : 'repositories'} that loaded successfully.
        </div>
      </div>
    </div>
  </div>
{/if}

<!-- Repositories grid with stacks -->
{#if !isLoading && !error}
  {#if filteredRepos.length > 0}
    <div class="space-y-4">
      {#each filteredRepos as repo}
        <div class="bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)] shadow-sm">
          <!-- Repository header (clickable to expand/collapse) -->
          <button
            on:click={() => toggleRepo(repo.repo)}
            class="w-full px-6 py-4 text-left hover:bg-[var(--sg-bg-2)] transition-colors rounded-t-lg"
          >
            <div class="flex items-start justify-between">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-3 mb-2">
                  <svg class="w-5 h-5 transition-transform {expandedRepos.has(repo.repo) ? 'rotate-90' : ''}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                  </svg>
                  <h3 class="text-lg font-semibold text-[var(--sg-text)]">
                    {repo.repo}
                  </h3>
                  <span class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium {getStateBadgeClasses(repo.aggregateState)}">
                    {formatStateName(repo.aggregateState)}
                  </span>
                </div>
                <div class="flex items-center gap-4 text-sm text-[var(--sg-text-dim)] ml-8">
                  <span>{repo.totalStacks} {repo.totalStacks === 1 ? 'stack' : 'stacks'}</span>
                  <span>•</span>
                  <span>{repo.totalPRs} {repo.totalPRs === 1 ? 'PR' : 'PRs'}</span>
                </div>
              </div>
            </div>
          </button>

          <!-- Stacks list (expanded) -->
          {#if expandedRepos.has(repo.repo)}
            <div class="border-t border-[var(--sg-border)] p-4 space-y-2 bg-[var(--sg-bg-0)]">
              {#each repo.stacks as stack}
                <div class="p-3 rounded-md bg-[var(--sg-bg-1)] border border-[var(--sg-border)]">
                  <div class="flex items-center justify-between">
                    <div class="flex-1 min-w-0">
                      <div class="font-medium text-[var(--sg-text)] mb-1">
                        {stack.stackName}
                      </div>
                      <div class="flex flex-wrap gap-1.5 text-xs">
                        {#each stack.dirspaces as ds}
                          <span class="font-mono bg-[var(--sg-bg-2)] px-1.5 py-0.5 rounded text-[var(--sg-text-dim)]">
                            {ds.dir}:{ds.workspace}
                          </span>
                        {/each}
                      </div>
                      {#if stack.prs.length > 0}
                        <div class="text-xs text-[var(--sg-text-dim)] mt-1">
                          PRs: {stack.prs.map(pr => `#${pr.prNumber}`).join(', ')}
                        </div>
                      {/if}
                    </div>
                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium {getStateBadgeClasses(stack.state)} ml-3">
                      {formatStateName(stack.state)}
                    </span>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        </div>
      {/each}
    </div>
  {:else}
    <!-- Empty state -->
    <EmptyState
      icon="mdi:folder-outline"
      title="No repositories found"
      description={searchQuery
        ? 'No repositories match your search. Try adjusting your search query.'
        : `No repositories with stacks in the last ${timeRange} days.`}
    />
  {/if}
{/if}
