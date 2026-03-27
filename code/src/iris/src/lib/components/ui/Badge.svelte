<script lang="ts">
  export let variant: 'accent' | 'success' | 'error' | 'warning' | 'purple' | 'pink' | 'orange' | 'neutral' = 'neutral';
  export let size: 'sm' | 'md' = 'sm';

  const variantClasses = {
    accent: 'bg-[var(--sg-accent-bg)] text-[var(--sg-accent)]',
    success: 'bg-[var(--sg-success-bg)] text-[var(--sg-success)]',
    error: 'bg-[var(--sg-error-bg)] text-[var(--sg-error)]',
    warning: 'bg-[var(--sg-warning-bg)] text-[var(--sg-warning)]',
    purple: 'bg-[var(--sg-purple-bg)] text-[var(--sg-purple)]',
    pink: 'bg-[var(--sg-pink-bg)] text-[var(--sg-pink)]',
    orange: 'bg-[var(--sg-orange-bg)] text-[var(--sg-orange)]',
    neutral: 'bg-[var(--sg-bg-2)] text-[var(--sg-text-dim)]'
  };

  const sizeClasses = {
    sm: 'px-2 py-0.5 text-xs',
    md: 'px-3 py-1 text-sm'
  };
</script>

<span class="inline-flex items-center rounded-full font-medium {variantClasses[variant]} {sizeClasses[size]} {$$props.class || ''}">
  <slot />
</span>
