<script lang="ts">
  import TimelineEventCard from './TimelineEventCard.svelte';
  import { LoadingSpinner } from '../index';
  import type { TimelineEvent } from '../../types';

  // Props
  export let timelineEvents: TimelineEvent[];
  export let isLoading: boolean;
  export let error: string | null;
  export let searchQuery: string;
  export let timeRange: number;
  export let onRefresh: () => void;

  // Local state
  let runTypeFilter: string = ''; // 'apply' | 'plan' | 'index' | ''
  let stateFilter: string = ''; // 'success' | 'failure' | 'running' | ''
  let filteredEvents: TimelineEvent[] = [];

  /**
   * Applies current filters
   */
  function applyFilters(): void {
    let filtered = [...timelineEvents];

    // Filter by run type
    if (runTypeFilter) {
      filtered = filtered.filter(event => event.runType === runTypeFilter);
    }

    // Filter by state
    if (stateFilter) {
      filtered = filtered.filter(event => event.runState === stateFilter);
    }

    // Filter by search query (PR number, title, repo, user, stack, dir)
    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase().trim();
      filtered = filtered.filter(event => {
        // Search in PR number
        if (event.prNumber && event.prNumber.toString().includes(query)) {
          return true;
        }

        // Search in PR title
        if (event.prTitle && event.prTitle.toLowerCase().includes(query)) {
          return true;
        }

        // Search in repo
        if (event.repo.toLowerCase().includes(query)) {
          return true;
        }

        // Search in user
        if (event.user && event.user.toLowerCase().includes(query)) {
          return true;
        }

        // Search in stack name
        if (event.stackName && event.stackName.toLowerCase().includes(query)) {
          return true;
        }

        // Search in dir
        if (event.dir.toLowerCase().includes(query)) {
          return true;
        }

        // Search in workspace
        if (event.workspace.toLowerCase().includes(query)) {
          return true;
        }

        return false;
      });
    }

    filteredEvents = filtered;
  }

  /**
   * Resets filters
   */
  function resetFilters(): void {
    runTypeFilter = '';
    stateFilter = '';
    applyFilters();
  }

  // Reactive statements
  $: if (timelineEvents || searchQuery !== undefined || runTypeFilter !== undefined || stateFilter !== undefined) {
    applyFilters();
  }

  $: hasActiveFilters = runTypeFilter !== '' || stateFilter !== '';
</script>

<!-- Filter buttons -->
<div class="mb-4 flex items-center gap-2 flex-wrap">
  <span class="text-sm font-medium text-[var(--sg-text-muted)]">Quick Filters:</span>

  <!-- Run Type Filters -->
  <button
    on:click={() => { runTypeFilter = ''; applyFilters(); }}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {runTypeFilter === ''
      ? 'bg-[var(--sg-accent-button)] text-white'
      : 'bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)] hover:opacity-90'}"
    aria-label="Show all run types"
    aria-pressed={runTypeFilter === ''}
  >
    All Types
  </button>
  <button
    on:click={() => { runTypeFilter = 'apply'; applyFilters(); }}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {runTypeFilter === 'apply'
      ? 'bg-[var(--sg-accent-button)] text-white'
      : 'bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)] hover:opacity-90'}"
    aria-label="Show apply runs"
    aria-pressed={runTypeFilter === 'apply'}
  >
    🚀 Apply
  </button>
  <button
    on:click={() => { runTypeFilter = 'plan'; applyFilters(); }}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {runTypeFilter === 'plan'
      ? 'bg-[var(--sg-accent-button)] text-white'
      : 'bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)] hover:opacity-90'}"
    aria-label="Show plan runs"
    aria-pressed={runTypeFilter === 'plan'}
  >
    📋 Plan
  </button>

  <span class="text-[var(--sg-text-dim)]">|</span>

  <!-- State Filters -->
  <button
    on:click={() => { stateFilter = 'success'; applyFilters(); }}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'success'
      ? 'bg-[var(--sg-success)] text-white'
      : 'bg-[var(--sg-success-bg)] text-[var(--sg-success)] hover:bg-[var(--sg-success-bg)] hover:opacity-90'}"
    aria-label="Show successful runs"
    aria-pressed={stateFilter === 'success'}
  >
    ✅ Success
  </button>
  <button
    on:click={() => { stateFilter = 'failure'; applyFilters(); }}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'failure'
      ? 'bg-[var(--sg-error)] text-white'
      : 'bg-[var(--sg-error-bg)] text-[var(--sg-error)] hover:bg-[var(--sg-error-bg)] hover:opacity-90'}"
    aria-label="Show failed runs"
    aria-pressed={stateFilter === 'failure'}
  >
    ❌ Failed
  </button>
  <button
    on:click={() => { stateFilter = 'running'; applyFilters(); }}
    class="px-3 py-1 rounded-md text-sm font-medium transition-colors {stateFilter === 'running'
      ? 'bg-[var(--sg-accent-button)] text-white'
      : 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] hover:bg-[var(--sg-accent-bg)] hover:opacity-90'}"
    aria-label="Show running runs"
    aria-pressed={stateFilter === 'running'}
  >
    🔄 Running
  </button>

  {#if hasActiveFilters}
    <button
      on:click={resetFilters}
      class="px-3 py-1 rounded-md text-sm font-medium bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)] hover:bg-[var(--sg-bg-2)] hover:opacity-90 transition-colors"
    >
      Reset Filters
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
          Error loading timeline
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

<!-- Timeline table -->
{:else}
  {#if filteredEvents.length > 0}
    <div class="bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)] overflow-hidden shadow-sm">
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-[var(--sg-border)]">
          <thead class="bg-[var(--sg-bg-0)]">
            <tr>
              <th class="px-3 py-3 text-left text-xs font-medium text-[var(--sg-text-dim)] uppercase tracking-wider">
                Time
              </th>
              <th class="px-3 py-3 text-left text-xs font-medium text-[var(--sg-text-dim)] uppercase tracking-wider">
                Type
              </th>
              <th class="px-3 py-3 text-left text-xs font-medium text-[var(--sg-text-dim)] uppercase tracking-wider">
                State
              </th>
              <th class="px-3 py-3 text-left text-xs font-medium text-[var(--sg-text-dim)] uppercase tracking-wider">
                PR
              </th>
              <th class="px-3 py-3 text-left text-xs font-medium text-[var(--sg-text-dim)] uppercase tracking-wider">
                Repository
              </th>
              <th class="px-3 py-3 text-left text-xs font-medium text-[var(--sg-text-dim)] uppercase tracking-wider">
                Stack / Dir:Workspace
              </th>
              <th class="px-3 py-3 text-left text-xs font-medium text-[var(--sg-text-dim)] uppercase tracking-wider">
                User
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-[var(--sg-border)]">
            {#each filteredEvents as event}
              <TimelineEventCard {event} />
            {/each}
          </tbody>
        </table>
      </div>

      <!-- Info about showing limited events -->
      {#if timelineEvents.length >= 100}
        <div class="px-4 py-3 bg-[var(--sg-bg-0)] border-t border-[var(--sg-border)] text-center text-xs text-[var(--sg-text-dim)]">
          Showing the 100 most recent events from the last {timeRange} days
        </div>
      {/if}
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
          d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
        />
      </svg>
      <h3 class="mt-2 text-sm font-semibold text-[var(--sg-text)]">No events found</h3>
      <p class="mt-1 text-sm text-[var(--sg-text-dim)]">
        {#if hasActiveFilters || searchQuery}
          No events match your current filters. Try adjusting or resetting your filters.
        {:else}
          No events in the last {timeRange} days.
        {/if}
      </p>
    </div>
  {/if}
{/if}
