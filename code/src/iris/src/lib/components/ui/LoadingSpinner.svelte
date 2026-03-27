<script lang="ts">
  export let size: 'sm' | 'md' | 'lg' | 'xl' = 'md';
  export let color: 'accent' | 'error' | 'success' | 'white' = 'accent';
  export let centered: boolean = true;

  const sizeClasses = {
    sm: 'h-4 w-4',
    md: 'h-6 w-6',
    lg: 'h-8 w-8',
    xl: 'h-12 w-12'
  };

  const colorClasses = {
    accent: 'border-[var(--sg-accent)]',
    error: 'border-[var(--sg-error)]',
    success: 'border-[var(--sg-success)]',
    white: 'border-white'
  };

  const containerClasses = centered ? 'flex justify-center py-12' : '';
</script>

<div class={containerClasses}>
  <div class="animate-spin rounded-full border-b-2 {colorClasses[color]} {sizeClasses[size]}"></div>
</div>
