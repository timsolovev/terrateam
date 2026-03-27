<script lang="ts">
  import type { PRWithStacks } from '../../types';
  import { navigateToStackDetail } from '../../utils/navigation';

  export let prWithStacks: PRWithStacks;
  export let expanded: boolean = false;

  // Display logic
  $: displayedStacks = expanded
    ? prWithStacks.stacks
    : prWithStacks.stacks.slice(0, 5);
  $: hasMoreStacks = prWithStacks.stacks.length > 5;

  /**
   * Gets color classes for aggregate state border
   */
  function getStateBorderColor(state: string): string {
    switch (state) {
      case 'success':
        return 'border-l-[var(--sg-success)]';
      case 'failed':
        return 'border-l-[var(--sg-error)]';
      case 'pending':
        return 'border-l-[var(--sg-purple)]';
      case 'ready':
        return 'border-l-[var(--sg-accent)]';
      case 'no_changes':
        return 'border-l-[var(--sg-text-dim)]';
      default:
        return 'border-l-[var(--sg-text-dim)]';
    }
  }

  /**
   * Gets badge classes for aggregate state
   */
  function getStateBadgeClasses(state: string): string {
    switch (state) {
      case 'success':
        return 'bg-[var(--sg-success-bg)] text-[var(--sg-success)]';
      case 'failed':
        return 'bg-[var(--sg-error-bg)] text-[var(--sg-error)]';
      case 'pending':
        return 'bg-[var(--sg-purple-bg)] text-[var(--sg-purple)]';
      case 'ready':
        return 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)]';
      case 'no_changes':
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)]';
      default:
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)]';
    }
  }

  /**
   * Gets badge classes for individual stack state
   */
  function getStackStateBadgeClasses(state: string): string {
    switch (state) {
      case 'apply_success':
        return 'bg-[var(--sg-success-bg)] text-[var(--sg-success)]';
      case 'apply_failed':
      case 'plan_failed':
        return 'bg-[var(--sg-error-bg)] text-[var(--sg-error)]';
      case 'apply_pending':
      case 'plan_pending':
        return 'bg-[var(--sg-purple-bg)] text-[var(--sg-purple)]';
      case 'apply_ready':
        return 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)]';
      case 'no_changes':
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)]';
      default:
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)]';
    }
  }

  /**
   * Gets icon for stack state
   */
  function getStackStateIcon(state: string): string {
    switch (state) {
      case 'apply_success':
        return '✅';
      case 'apply_failed':
      case 'plan_failed':
        return '❌';
      case 'apply_pending':
      case 'plan_pending':
        return '⏳';
      case 'apply_ready':
        return '✓';
      case 'no_changes':
        return '○';
      default:
        return '▪️';
    }
  }

  /**
   * Formats state name for display
   */
  function formatStateName(state: string): string {
    return state.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  }

  /**
   * Formats timestamp as relative time
   */
  function formatRelativeTime(timestamp: string): string {
    try {
      const now = new Date();
      const date = new Date(timestamp);
      const diffMs = now.getTime() - date.getTime();
      const diffMins = Math.floor(diffMs / (1000 * 60));
      const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
      const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
      const diffWeeks = Math.floor(diffDays / 7);

      if (diffMins < 60) {
        return diffMins === 0 ? 'Just now' : `${diffMins}m ago`;
      } else if (diffHours < 24) {
        return diffHours === 0 ? 'Just now' : `${diffHours}h ago`;
      } else if (diffDays < 7) {
        return `${diffDays}d ago`;
      } else if (diffWeeks < 4) {
        return `${diffWeeks}w ago`;
      } else {
        return date.toLocaleDateString();
      }
    } catch {
      return timestamp;
    }
  }

  /**
   * Toggles expansion
   */
  function toggleExpand(event: MouseEvent): void {
    event.stopPropagation();
    expanded = !expanded;
  }

  /**
   * Navigates to stack detail for this PR
   */
  function handleClick(): void {
    // Navigate to PR's stack detail page
    // Using first stack name as default (user can navigate to specific stacks from detail page)
    if (prWithStacks.stacks.length > 0) {
      const firstStackName = `${prWithStacks.stacks[0].stackOuter.name}/${prWithStacks.stacks[0].stackInner.name}`;
      navigateToStackDetail(prWithStacks.prNumber, firstStackName);
    }
  }
</script>

<button
  class="w-full text-left bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)] border-l-4 {getStateBorderColor(
    prWithStacks.aggregateState
  )} shadow-sm hover:shadow-lg transition-shadow cursor-pointer"
  aria-label="View PR #{prWithStacks.prNumber} in {prWithStacks.repo} with {prWithStacks.stacks.length} stacks"
  on:click={handleClick}
>
  <div class="p-6">
    <!-- Header: PR info and aggregate state -->
    <div class="flex items-start justify-between mb-4">
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 mb-2">
          <h3 class="text-lg font-semibold text-[var(--sg-text)]">
            PR #{prWithStacks.prNumber}
            {#if prWithStacks.prTitle}
              <span class="text-[var(--sg-text-dim)]">: {prWithStacks.prTitle}</span>
            {/if}
          </h3>
        </div>
        <div class="flex items-center gap-2">
          <span
            class="inline-flex items-center px-2 py-1 rounded-md text-xs font-medium bg-[var(--sg-bg-2)] text-[var(--sg-text-muted)]"
          >
            {prWithStacks.repo}
          </span>
        </div>
      </div>
      <div class="flex-shrink-0 ml-4">
        <span
          class="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium {getStateBadgeClasses(
            prWithStacks.aggregateState
          )}"
        >
          {formatStateName(prWithStacks.aggregateState)}
        </span>
      </div>
    </div>

    <!-- Stack summary counts -->
    <div class="mb-4 bg-[var(--sg-bg-0)] rounded-md p-3">
      <div class="flex items-center justify-between flex-wrap gap-2">
        <div class="text-sm font-medium text-[var(--sg-text)]">
          {prWithStacks.stacks.length} {prWithStacks.stacks.length === 1 ? 'Stack' : 'Stacks'}
        </div>
        <div class="flex items-center gap-3 text-xs flex-wrap">
          {#if prWithStacks.stackStateCounts.apply_failed > 0}
            <div class="flex items-center gap-1 text-[var(--sg-error)]">
              <span class="w-2 h-2 rounded-full bg-[var(--sg-error)]"></span>
              <span>{prWithStacks.stackStateCounts.apply_failed} apply failed</span>
            </div>
          {/if}
          {#if prWithStacks.stackStateCounts.plan_failed > 0}
            <div class="flex items-center gap-1 text-[var(--sg-orange)]">
              <span class="w-2 h-2 rounded-full bg-[var(--sg-orange)]"></span>
              <span>{prWithStacks.stackStateCounts.plan_failed} plan failed</span>
            </div>
          {/if}
          {#if prWithStacks.stackStateCounts.apply_pending > 0}
            <div class="flex items-center gap-1 text-[var(--sg-purple)]">
              <span class="w-2 h-2 rounded-full bg-[var(--sg-purple)]"></span>
              <span>{prWithStacks.stackStateCounts.apply_pending} apply pending</span>
            </div>
          {/if}
          {#if prWithStacks.stackStateCounts.plan_pending > 0}
            <div class="flex items-center gap-1 text-[var(--sg-pink)]">
              <span class="w-2 h-2 rounded-full bg-[var(--sg-pink)]"></span>
              <span>{prWithStacks.stackStateCounts.plan_pending} plan pending</span>
            </div>
          {/if}
          {#if prWithStacks.stackStateCounts.apply_ready > 0}
            <div class="flex items-center gap-1 text-[var(--sg-accent)]">
              <span class="w-2 h-2 rounded-full bg-[var(--sg-accent)]"></span>
              <span>{prWithStacks.stackStateCounts.apply_ready} ready</span>
            </div>
          {/if}
          {#if prWithStacks.stackStateCounts.apply_success > 0}
            <div class="flex items-center gap-1 text-[var(--sg-success)]">
              <span class="w-2 h-2 rounded-full bg-[var(--sg-success)]"></span>
              <span>{prWithStacks.stackStateCounts.apply_success} successful</span>
            </div>
          {/if}
          {#if prWithStacks.stackStateCounts.no_changes > 0}
            <div class="flex items-center gap-1 text-[var(--sg-text-dim)]">
              <span class="w-2 h-2 rounded-full bg-[var(--sg-text-dim)]"></span>
              <span>{prWithStacks.stackStateCounts.no_changes} no changes</span>
            </div>
          {/if}
        </div>
      </div>
    </div>

    <!-- Stacks list -->
    <div class="space-y-2 mb-4">
      {#each displayedStacks as stack}
        <div
          class="flex items-center justify-between p-2 rounded-md bg-[var(--sg-bg-0)] hover:bg-[var(--sg-bg-2)] transition-colors"
        >
          <div class="flex items-center gap-2 min-w-0 flex-1">
            <span class="flex-shrink-0 text-base" aria-hidden="true">
              {getStackStateIcon(stack.state)}
            </span>
            <span class="font-medium text-[var(--sg-text)] truncate">
              {stack.stackOuter.name}
              {#if stack.stackOuter.name !== stack.stackInner.name}
                <span class="text-[var(--sg-text-dim)]">/</span>
                {stack.stackInner.name}
              {/if}
            </span>
          </div>
          <div class="flex items-center gap-2 flex-shrink-0">
            {#if stack.recentRunsCount > 0}
              <span class="text-xs text-[var(--sg-text-dim)]">
                {stack.recentRunsCount} {stack.recentRunsCount === 1 ? 'run' : 'runs'}
              </span>
            {/if}
            <span
              class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium {getStackStateBadgeClasses(
                stack.state
              )}"
            >
              {formatStateName(stack.state)}
            </span>
          </div>
        </div>
      {/each}

      {#if hasMoreStacks}
        <button
          on:click={toggleExpand}
          class="w-full text-center text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] font-medium transition-colors py-2"
          aria-label="{expanded ? 'Show fewer' : 'Show all'} stacks"
          aria-expanded={expanded}
        >
          {expanded
            ? 'Show less'
            : `Show all ${prWithStacks.stacks.length} stacks (+${prWithStacks.stacks.length - 5} more)`}
        </button>
      {/if}
    </div>

    <!-- Metrics footer -->
    <div
      class="flex items-center gap-4 pt-3 border-t border-[var(--sg-border)] text-xs text-[var(--sg-text-dim)]"
    >
      {#if prWithStacks.lastActivity}
        <div class="flex items-center gap-1">
          <span class="font-medium">Last activity:</span>
          <span>{formatRelativeTime(prWithStacks.lastActivity)}</span>
          {#if prWithStacks.lastUser}
            <span>by @{prWithStacks.lastUser}</span>
          {/if}
        </div>
      {/if}
      {#if prWithStacks.totalRunningCount > 0}
        <div class="flex items-center gap-1">
          <span class="w-2 h-2 rounded-full bg-[var(--sg-accent)]"></span>
          <span>{prWithStacks.totalRunningCount} running</span>
        </div>
      {/if}
      {#if prWithStacks.totalFailureCount > 0}
        <div class="flex items-center gap-1">
          <span class="w-2 h-2 rounded-full bg-[var(--sg-error)]"></span>
          <span>{prWithStacks.totalFailureCount} failed runs</span>
        </div>
      {/if}
      {#if prWithStacks.totalSuccessCount > 0}
        <div class="flex items-center gap-1">
          <span class="w-2 h-2 rounded-full bg-[var(--sg-success)]"></span>
          <span>{prWithStacks.totalSuccessCount} successful runs</span>
        </div>
      {/if}
    </div>
  </div>
</button>
