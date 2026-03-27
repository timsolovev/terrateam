<script lang="ts">
  import type { HTMLButtonAttributes } from 'svelte/elements';

  interface $$Props extends HTMLButtonAttributes {
    variant?: 'primary' | 'secondary' | 'accent' | 'outline' | 'ghost' | 'danger';
    size?: 'sm' | 'md' | 'lg';
    loading?: boolean;
    disabled?: boolean;
    fullWidth?: boolean;
  }

  export let variant: $$Props['variant'] = 'primary';
  export let size: $$Props['size'] = 'md';
  export let loading: $$Props['loading'] = false;
  export let disabled: $$Props['disabled'] = false;
  export let fullWidth: $$Props['fullWidth'] = false;

  const baseClasses = 'inline-flex items-center justify-center font-semibold rounded-[var(--sg-button-radius)] transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2';

  const variantClasses = {
    primary: 'bg-[var(--sg-accent-button)] text-white border border-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] focus:ring-[var(--sg-accent)]',
    secondary: 'bg-[var(--sg-bg-1)] text-[var(--sg-text)] border border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)] focus:ring-[var(--sg-border)]',
    accent: 'bg-[var(--sg-accent-button)] text-white hover:bg-[var(--sg-accent-button-hover)] focus:ring-[var(--sg-accent)]',
    outline: 'bg-transparent text-[var(--sg-text)] border border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)] focus:ring-[var(--sg-accent)]',
    ghost: 'bg-transparent text-[var(--sg-text)] hover:bg-[var(--sg-bg-2)] focus:ring-[var(--sg-accent)]',
    danger: 'bg-[var(--sg-error)] text-white hover:opacity-90 focus:ring-[var(--sg-error)]'
  };

  const sizeClasses = {
    sm: 'px-3 py-1 text-sm',
    md: 'px-4 py-2 text-sm',
    lg: 'px-6 py-3 text-base'
  };

  $: classes = [
    baseClasses,
    variant ? variantClasses[variant] : '',
    size ? sizeClasses[size] : '',
    fullWidth ? 'w-full' : '',
    (disabled || loading) ? 'opacity-50 cursor-not-allowed' : '',
    $$props.class || ''
  ].filter(Boolean).join(' ');

  $: isDisabled = disabled || loading;
</script>

<button
  {...$$restProps}
  class={classes}
  disabled={isDisabled}
  on:click
  on:mouseenter
  on:mouseleave
  on:focus
  on:blur
>
  {#if loading}
    <svg class="animate-spin -ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
    </svg>
  {/if}
  <slot />
</button>

