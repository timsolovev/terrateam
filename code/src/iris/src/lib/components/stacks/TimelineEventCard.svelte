<script lang="ts">
  import type { TimelineEvent } from '../../types';
  import { navigateToStackDetail } from '../../utils/navigation';

  export let event: TimelineEvent;

  /**
   * Handles click on timeline entry
   */
  function handleClick(): void {
    // If we have PR number and stack name, navigate to stack detail
    if (event.prNumber && event.stackName) {
      navigateToStackDetail(event.prNumber, event.stackName);
    }
    // Could add fallback navigation to runs page or PR page if needed
  }

  /**
   * Gets icon for run type
   */
  function getRunTypeIcon(runType: string): string {
    switch (runType) {
      case 'apply':
        return '🚀';
      case 'plan':
        return '📋';
      case 'index':
        return '🔍';
      case 'build-config':
        return '⚙️';
      case 'build-tree':
        return '🌳';
      default:
        return '▪️';
    }
  }

  /**
   * Gets badge classes for run state
   */
  function getRunStateBadgeClasses(state: string): string {
    switch (state) {
      case 'success':
        return 'bg-[var(--sg-success-bg)] text-[var(--sg-success)]';
      case 'failure':
        return 'bg-[var(--sg-error-bg)] text-[var(--sg-error)]';
      case 'running':
        return 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)]';
      case 'queued':
        return 'bg-[var(--sg-purple-bg)] text-[var(--sg-purple)]';
      case 'aborted':
        return 'bg-[var(--sg-orange-bg)] text-[var(--sg-orange)]';
      default:
        return 'bg-[var(--sg-bg-2)] text-[var(--sg-text)]';
    }
  }

  /**
   * Formats state name for display
   */
  function formatStateName(state: string): string {
    return state.charAt(0).toUpperCase() + state.slice(1);
  }

  /**
   * Formats run type for display
   */
  function formatRunType(runType: string): string {
    return runType.replace(/-/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
  }

  /**
   * Formats timestamp
   */
  function formatTime(timestamp: string): string {
    try {
      const date = new Date(timestamp);
      return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
    } catch {
      return timestamp;
    }
  }

  /**
   * Formats full timestamp for tooltip
   */
  function formatFullTimestamp(timestamp: string): string {
    try {
      const date = new Date(timestamp);
      return date.toLocaleString();
    } catch {
      return timestamp;
    }
  }
</script>

<tr
  class="hover:bg-[var(--sg-bg-2)] border-b border-[var(--sg-border)] cursor-pointer transition-colors"
  on:click={handleClick}
  role="button"
  tabindex="0"
  on:keydown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); handleClick(); } }}
  aria-label="View details for {event.runType} run {event.prNumber ? `on PR #${event.prNumber}` : `in ${event.repo}`}"
>
  <!-- Time -->
  <td class="px-3 py-2 text-xs text-[var(--sg-text-dim)] whitespace-nowrap" title={formatFullTimestamp(event.timestamp)}>
    {formatTime(event.timestamp)}
  </td>

  <!-- Type -->
  <td class="px-3 py-2">
    <div class="flex items-center gap-2">
      <span class="text-base" aria-hidden="true">{getRunTypeIcon(event.runType)}</span>
      <span class="text-xs font-medium text-[var(--sg-text-muted)]">{formatRunType(event.runType)}</span>
    </div>
  </td>

  <!-- State -->
  <td class="px-3 py-2">
    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium {getRunStateBadgeClasses(event.runState)}">
      {formatStateName(event.runState)}
    </span>
  </td>

  <!-- PR -->
  <td class="px-3 py-2 text-xs text-[var(--sg-text-muted)]">
    {#if event.prNumber}
      <div class="flex flex-col">
        <span class="font-medium">#{event.prNumber}</span>
        {#if event.prTitle}
          <span class="text-[var(--sg-text-dim)] truncate max-w-xs">{event.prTitle}</span>
        {/if}
      </div>
    {:else}
      <span class="text-[var(--sg-text-dim)]">-</span>
    {/if}
  </td>

  <!-- Repo -->
  <td class="px-3 py-2 text-xs font-mono text-[var(--sg-text-dim)]">
    {event.repo}
  </td>

  <!-- Stack / Dir:Workspace -->
  <td class="px-3 py-2">
    <div class="flex flex-col gap-0.5">
      {#if event.stackName}
        <span class="text-xs font-medium text-[var(--sg-text-muted)]">{event.stackName}</span>
      {/if}
      <span class="text-xs font-mono bg-[var(--sg-bg-2)] px-1.5 py-0.5 rounded text-[var(--sg-text-dim)] inline-block">
        {event.dir}:{event.workspace}
      </span>
    </div>
  </td>

  <!-- User -->
  <td class="px-3 py-2 text-xs text-[var(--sg-text-dim)]">
    {#if event.user}
      @{event.user}
    {:else}
      <span class="text-[var(--sg-text-dim)]">-</span>
    {/if}
  </td>
</tr>
