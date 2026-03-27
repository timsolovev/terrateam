<script lang="ts">
  import type { HTMLButtonAttributes } from 'svelte/elements';

  interface $$Props extends HTMLButtonAttributes {
    padding?: 'none' | 'sm' | 'md' | 'lg';
    border?: boolean;
    shadow?: boolean;
    hover?: boolean;
    disabled?: boolean;
  }

  export let padding: $$Props['padding'] = 'md';
  export let border: $$Props['border'] = true;
  export let shadow: $$Props['shadow'] = true;
  export let hover: $$Props['hover'] = true;
  export let disabled: $$Props['disabled'] = false;

  const paddingClasses = {
    none: '',
    sm: 'p-4',
    md: 'p-6',
    lg: 'p-8'
  };

  $: classes = [
    'bg-[var(--sg-bg-1)] rounded-lg w-full text-left',
    border ? 'border border-[var(--sg-border)]' : '',
    shadow ? 'shadow-sm' : '',
    hover && !disabled ? 'hover:shadow-lg transition-shadow' : '',
    disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer',
    'focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)] focus:ring-offset-2',
    padding ? paddingClasses[padding] : '',
    $$props.class || ''
  ].filter(Boolean).join(' ');
</script>

<!-- 
  Accessible clickable card using button element
  Provides proper keyboard navigation, focus management, and screen reader support
-->
<button
  {...$$restProps}
  class={classes}
  {disabled}
  on:click
  on:keydown
  on:focus
  on:blur
>
  <slot />
</button>