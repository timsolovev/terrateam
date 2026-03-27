<script lang="ts">
  import type { StackInner, StackOuter } from '../../types';
  import StackStateIndicator from './StackStateIndicator.svelte';

  // Can be either an outer or inner stack
  export let stack: StackOuter | StackInner;
  export let level: number = 0;
  export let forceExpanded: boolean = true;
  export let showWorkspaces: boolean = false;

  let expanded: boolean = true;

  // React to forceExpanded changes
  $: expanded = forceExpanded;

  function isStackOuter(s: StackOuter | StackInner): s is StackOuter {
    return 'stacks' in s && Array.isArray((s as StackOuter).stacks);
  }

  function isStackInner(s: StackOuter | StackInner): s is StackInner {
    return 'dirspaces' in s && Array.isArray((s as StackInner).dirspaces);
  }

  // Get background color class based on state and nesting level
  function getBackgroundClass(level: number): string {
    if (level === 0) {
      // Outer most boxes - darker background
      return 'bg-[var(--sg-bg-2)]';
    } else if (level === 1) {
      // Nested boxes - lighter background
      return 'bg-[var(--sg-bg-1)]';
    } else {
      // Deeper nesting
      return 'bg-[var(--sg-bg-0)]';
    }
  }

  // Get border width based on level
  function getBorderClass(level: number): string {
    if (level === 0) {
      return 'border-4';
    } else if (level === 1) {
      return 'border-2';
    } else {
      return 'border';
    }
  }

  // Get state-based border color
  function getBorderColorClass(state: string): string {
    switch (state) {
      case 'no_changes':
        return 'border-[var(--sg-border)]';
      case 'plan_failed':
        return 'border-[var(--sg-orange)]';
      case 'plan_pending':
        return 'border-[var(--sg-pink)]';
      case 'apply_failed':
        return 'border-[var(--sg-error)]';
      case 'apply_pending':
        return 'border-[var(--sg-purple)]';
      case 'apply_ready':
        return 'border-[var(--sg-accent)]';
      case 'apply_success':
        return 'border-[var(--sg-success)]';
      default:
        return 'border-[var(--sg-border)]';
    }
  }

  // Get color for state indicator dots
  function getStateDotColor(state: string): string {
    switch (state) {
      case 'apply_success':
        return 'bg-[var(--sg-success)]';
      case 'apply_failed':
        return 'bg-[var(--sg-error)]';
      case 'apply_pending':
        return 'bg-[var(--sg-purple)]';
      case 'apply_ready':
        return 'bg-[var(--sg-accent)]';
      case 'plan_pending':
        return 'bg-[var(--sg-pink)]';
      case 'plan_failed':
        return 'bg-[var(--sg-orange)]';
      case 'no_changes':
        return 'bg-[var(--sg-text-dim)]';
      default:
        return 'bg-[var(--sg-text-dim)]';
    }
  }

  // Count workspaces by state for inner stacks
  function getWorkspaceStateCounts(stack: StackOuter | StackInner): Record<string, number> {
    if (!isStackInner(stack)) {
      return {};
    }

    const counts: Record<string, number> = {};
    stack.dirspaces.forEach(({ state }) => {
      counts[state] = (counts[state] || 0) + 1;
    });
    return counts;
  }

  $: bgClass = getBackgroundClass(level);
  $: borderWidthClass = getBorderClass(level);
  $: borderColorClass = getBorderColorClass(stack.state);
  $: workspaceStateCounts = getWorkspaceStateCounts(stack);

  function toggleExpanded() {
    expanded = !expanded;
  }
</script>

<div
  class="rounded-lg {borderWidthClass} {borderColorClass} {bgClass} p-4 mb-4 transition-all"
  role="article"
  aria-label="Stack {stack.name}"
>
  <!-- Stack header with name and state -->
  {#if isStackOuter(stack) && stack.stacks.length > 0}
    <!-- Expandable stack - entire header is clickable -->
    <button
      on:click={toggleExpanded}
      class="w-full flex items-center justify-between mb-3 text-left focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)] rounded p-2 -m-2 hover:bg-[var(--sg-bg-2)] transition-colors"
      aria-label="{expanded ? 'Collapse' : 'Expand'} {stack.name}"
      aria-expanded={expanded}
    >
      <div class="flex items-center gap-3">
        <svg
          class="w-5 h-5 transition-transform {expanded ? 'rotate-90' : ''} text-[var(--sg-text-dim)]"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 5l7 7-7 7"
          />
        </svg>
        <div class="flex flex-col gap-1">
          <h3 class="text-lg font-semibold text-[var(--sg-text)] {level > 0 ? 'ml-4' : ''}">
            {stack.name}
          </h3>
          {#if isStackInner(stack) && stack.dirspaces.length > 0}
            <div class="flex items-center gap-2 {level > 0 ? 'ml-4' : ''}">
              {#each Object.entries(workspaceStateCounts) as [state, count]}
                <div class="flex items-center gap-1" title="{count} workspace{count !== 1 ? 's' : ''} {state.replace(/_/g, ' ')}">
                  <div class="w-2 h-2 rounded-full {getStateDotColor(state)}"></div>
                  <span class="text-xs font-medium text-[var(--sg-text-muted)]">{count}</span>
                </div>
              {/each}
            </div>
          {/if}
        </div>
      </div>
      <StackStateIndicator state={stack.state} size="md" />
    </button>
  {:else}
    <!-- Non-expandable stack (leaf node) - not clickable -->
    <div class="flex items-center justify-between mb-3">
      <div class="flex flex-col gap-1">
        <h3 class="text-lg font-semibold text-[var(--sg-text)] {level > 0 ? 'ml-4' : ''}">
          {stack.name}
        </h3>
        {#if isStackInner(stack) && stack.dirspaces.length > 0}
          <div class="flex items-center gap-2 {level > 0 ? 'ml-4' : ''}">
            {#each Object.entries(workspaceStateCounts) as [state, count]}
              <div class="flex items-center gap-1" title="{count} workspace{count !== 1 ? 's' : ''} {state.replace(/_/g, ' ')}">
                <div class="w-2 h-2 rounded-full {getStateDotColor(state)}"></div>
                <span class="text-xs font-medium text-[var(--sg-text-muted)]">{count}</span>
              </div>
            {/each}
          </div>
        {/if}
      </div>
      <StackStateIndicator state={stack.state} size="md" />
    </div>
  {/if}

  {#if expanded}
    <!-- Render nested stacks (for StackOuter) -->
    {#if isStackOuter(stack) && stack.stacks.length > 0}
      <div class="mt-4 space-y-4">
        {#each stack.stacks as innerStack}
          <svelte:self stack={innerStack} level={level + 1} {forceExpanded} {showWorkspaces} />
        {/each}
      </div>
    {/if}

    <!-- Render dirspaces (for StackInner leaf nodes) -->
    {#if isStackInner(stack) && stack.dirspaces.length > 0 && showWorkspaces}
      <div class="mt-3 space-y-2 {level > 0 ? 'ml-4' : ''}">
        {#each stack.dirspaces as { dirspace, state }}
          <div
            class="flex items-center gap-3 p-2 rounded-md bg-[var(--sg-bg-0)] text-sm"
          >
            <div class="flex-1 font-mono text-xs text-[var(--sg-text-muted)]">
              {dirspace.dir}
            </div>
            <div class="text-xs font-medium text-[var(--sg-text-dim)]">
              {dirspace.workspace}
            </div>
            <div class="flex items-center gap-1.5 px-2 py-1 rounded bg-[var(--sg-bg-1)] border border-[var(--sg-border)]">
              <div class="w-2 h-2 rounded-full {getStateDotColor(state)}"></div>
              <span class="text-xs font-medium text-[var(--sg-text-muted)]">
                {state.replace(/_/g, ' ')}
              </span>
            </div>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</div>
