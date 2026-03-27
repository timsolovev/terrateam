<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import Button from '../ui/Button.svelte';

  export let token: string;
  export let tokenName: string;

  const dispatch = createEventDispatcher<{
    close: void;
  }>();

  let copied = false;

  async function handleCopy(): Promise<void> {
    try {
      await navigator.clipboard.writeText(token);
      copied = true;

      // Reset copied state after 2 seconds
      setTimeout(() => {
        copied = false;
      }, 2000);
    } catch (err) {
      console.error('Failed to copy token:', err);
    }
  }

  function handleClose(): void {
    dispatch('close');
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      handleClose();
    }
  }
</script>

<svelte:window on:keydown={handleKeydown} />

<div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
  <div class="bg-[var(--sg-bg-1)] rounded-lg shadow-xl max-w-2xl w-full">
    <!-- Header -->
    <div class="px-6 py-4 border-b border-[var(--sg-border)]">
      <div class="flex items-center">
        <div class="flex-shrink-0">
          <svg class="h-8 w-8 text-[var(--sg-success)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>
        <h2 class="ml-3 text-xl font-bold text-[var(--sg-text)]">Token Created Successfully</h2>
      </div>
    </div>

    <!-- Body -->
    <div class="px-6 py-4">
      <!-- Warning Banner -->
      <div class="mb-6 bg-[var(--sg-error-bg)] border-2 border-[var(--sg-error)] rounded-lg p-4">
        <div class="flex items-start">
          <svg class="w-6 h-6 text-[var(--sg-error)] mr-3 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
          </svg>
          <div>
            <p class="text-sm font-bold text-[var(--sg-error)] mb-1">
              Copy this token now - it won't be shown again!
            </p>
            <p class="text-xs text-[var(--sg-error)]">
              For security reasons, we can only show this token once. If you lose it, you'll need to create a new token.
            </p>
          </div>
        </div>
      </div>

      <!-- Token Name -->
      <div class="mb-4">
        <div class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
          Token Name
        </div>
        <div class="text-base font-semibold text-[var(--sg-text)]">
          {tokenName}
        </div>
      </div>

      <!-- Token Value -->
      <div class="mb-6">
        <div class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
          Access Token
        </div>
        <div class="relative">
          <div class="bg-[var(--sg-bg-0)] border border-[var(--sg-border)] rounded-lg p-4 break-all">
            <code class="text-sm font-mono text-[var(--sg-text)]">{token}</code>
          </div>
          <button
            on:click={handleCopy}
            class="absolute top-2 right-2 inline-flex items-center px-3 py-2 text-sm font-medium rounded-md transition-colors
              {copied
                ? 'bg-[var(--sg-success-bg)] text-[var(--sg-success)]'
                : 'bg-[var(--sg-bg-1)] text-[var(--sg-text-muted)] border border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)]'
              }"
            title={copied ? 'Copied!' : 'Copy to clipboard'}
          >
            {#if copied}
              <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
              </svg>
              Copied!
            {:else}
              <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
              Copy
            {/if}
          </button>
        </div>
      </div>

      <!-- Usage Instructions -->
      <div class="bg-[var(--sg-accent-bg)] border border-[var(--sg-accent)] rounded-lg p-4">
        <div class="flex items-start">
          <svg class="w-5 h-5 text-[var(--sg-accent)] mr-3 mt-0.5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <div class="text-sm text-[var(--sg-accent)]">
            <p class="font-medium mb-2">How to use this token:</p>
            <ol class="list-decimal list-inside space-y-1 text-xs">
              <li>Store the token in a secure location (password manager, environment variable)</li>
              <li>Use it in API requests by including it in the Authorization header</li>
              <li>Never commit the token to version control or share it publicly</li>
              <li>Revoke the token immediately if you suspect it has been compromised</li>
            </ol>
          </div>
        </div>
      </div>
    </div>

    <!-- Footer -->
    <div class="px-6 py-4 border-t border-[var(--sg-border)] flex justify-end">
      <Button variant="primary" size="md" on:click={handleClose}>
        I've Saved the Token
      </Button>
    </div>
  </div>
</div>
