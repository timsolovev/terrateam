<script lang="ts">
  export let padding: 'none' | 'sm' | 'md' | 'lg' = 'md';
  export let hover: boolean = false;
  export let border: boolean = true;
  export let shadow: boolean = true;

  const paddingClasses = {
    none: '',
    sm: 'p-4',
    md: 'p-6',
    lg: 'p-8'
  };

  $: classes = [
    'bg-[var(--sg-bg-1)] rounded-lg',
    border ? 'border border-[var(--sg-border)]' : '',
    shadow ? 'shadow-sm' : '',
    hover ? 'hover:shadow-lg transition-shadow cursor-pointer' : '',
    paddingClasses[padding],
    $$props.class || ''
  ].filter(Boolean).join(' ');
</script>

<div class={classes} on:click on:keydown role={$$props.role}>
  <slot />
</div>