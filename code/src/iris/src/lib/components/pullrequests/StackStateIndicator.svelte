<script lang="ts">
  import type { StackState } from '../../types';

  export let state: StackState;
  export let size: 'sm' | 'md' | 'lg' = 'md';

  // Map states to colors and labels
  function getStateStyles(state: StackState): { bgClass: string; textClass: string; label: string } {
    switch (state) {
      case 'no_changes':
        return {
          bgClass: 'bg-[var(--sg-bg-2)]',
          textClass: 'text-[var(--sg-text)]',
          label: 'No changes'
        };
      case 'plan_failed':
        return {
          bgClass: 'bg-[var(--sg-orange-bg)]',
          textClass: 'text-[var(--sg-orange)]',
          label: 'Plan failed'
        };
      case 'plan_pending':
        return {
          bgClass: 'bg-[var(--sg-pink-bg)]',
          textClass: 'text-[var(--sg-pink)]',
          label: 'Plan pending'
        };
      case 'apply_failed':
        return {
          bgClass: 'bg-[var(--sg-error-bg)]',
          textClass: 'text-[var(--sg-error)]',
          label: 'Apply failed'
        };
      case 'apply_pending':
        return {
          bgClass: 'bg-[var(--sg-purple-bg)]',
          textClass: 'text-[var(--sg-purple)]',
          label: 'Apply pending'
        };
      case 'apply_ready':
        return {
          bgClass: 'bg-[var(--sg-accent-bg)]',
          textClass: 'text-[var(--sg-accent)]',
          label: 'Apply ready'
        };
      case 'apply_success':
        return {
          bgClass: 'bg-[var(--sg-success-bg)]',
          textClass: 'text-[var(--sg-success)]',
          label: 'Applied successfully'
        };
      default:
        return {
          bgClass: 'bg-[var(--sg-bg-2)]',
          textClass: 'text-[var(--sg-text)]',
          label: 'Unknown'
        };
    }
  }

  $: stateStyles = getStateStyles(state);

  $: sizeClasses = size === 'sm'
    ? 'px-2 py-1 text-xs'
    : size === 'lg'
    ? 'px-4 py-2 text-base'
    : 'px-3 py-1.5 text-sm';
</script>

<span
  class="inline-flex items-center font-medium rounded-md {stateStyles.bgClass} {stateStyles.textClass} {sizeClasses}"
  role="status"
  aria-label="{stateStyles.label}"
>
  {stateStyles.label}
</span>
