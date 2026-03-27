<script lang="ts">
  import Icon from './Icon.svelte';

  export let icon: string = '';
  export let title: string;
  export let description: string = '';
</script>

<div class="text-center py-12">
  {#if icon}
    <div class="flex justify-center mb-3">
      <Icon {icon} width="40" height="40" class="text-[var(--sg-text-dim)]" />
    </div>
  {/if}
  <h3 class="text-base font-medium text-[var(--sg-text)]">{title}</h3>
  {#if description}
    <p class="mt-1 text-sm text-[var(--sg-text-dim)]">{description}</p>
  {/if}
  <slot />
</div>
