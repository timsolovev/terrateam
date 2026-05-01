<script lang="ts">
  import { api, isApiError } from '../../api';
  import type { Installation, ServerConfig } from '../../types';
  import { Icon, LoadingSpinner } from '../index';
  import GitLabTokenInstructions from '../gitlab/GitLabTokenInstructions.svelte';

  export let installation: Installation;
  export let serverConfig: ServerConfig | null;

  let token = '';
  let isSubmitting = false;
  let submitted = false;
  let error: string | null = null;
  let showInstructions = false;

  $: webBaseUrl = serverConfig?.gitlab?.web_base_url || 'https://gitlab.com';

  async function submit(): Promise<void> {
    if (!token.trim()) {
      error = 'Please enter an access token';
      return;
    }

    try {
      isSubmitting = true;
      error = null;
      submitted = false;
      await api.submitGitLabAccessToken(installation.id, token);
      submitted = true;
      token = '';
      setTimeout(() => { submitted = false; }, 4000);
    } catch (err) {
      console.error('Failed to submit access token:', err);
      if (isApiError(err)) {
        error = `Failed to submit access token: ${err.message}`;
      } else {
        error = 'Failed to submit access token. Please verify it is valid and try again.';
      }
    } finally {
      isSubmitting = false;
    }
  }
</script>

<div class="card-bg rounded-lg shadow border mb-6">
  <div class="px-4 py-6 md:px-6 md:py-8">
    <div class="flex items-start justify-between mb-4 gap-3">
      <div>
        <h2 class="text-xl font-bold text-[var(--sg-text)] mb-1">GitLab Access Token</h2>
        <p class="text-sm text-[var(--sg-text-muted)]">
          Rotate the access token Terrateam uses for <strong>{installation.name}</strong>.
        </p>
      </div>
    </div>

    <div class="mb-4">
      <button
        type="button"
        on:click={() => showInstructions = !showInstructions}
        class="inline-flex items-center text-sm text-[var(--sg-accent)] hover:underline"
        aria-expanded={showInstructions}
      >
        <Icon icon={showInstructions ? 'mdi:chevron-down' : 'mdi:chevron-right'} class="mr-1" width="16" />
        How to create a token
      </button>
      {#if showInstructions}
        <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mt-3 border border-[var(--sg-border)]">
          <GitLabTokenInstructions
            {webBaseUrl}
            groupName={installation.name}
            linkColorClass="text-[var(--sg-accent)] hover:text-[var(--sg-accent)]"
          />
        </div>
      {/if}
    </div>

    <div class="mb-4">
      <label for="gitlab-rotate-token" class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
        New Access Token
      </label>
      <input
        id="gitlab-rotate-token"
        type="password"
        bind:value={token}
        placeholder="Paste your new GitLab access token"
        class="w-full max-w-xl px-4 py-2 border border-[var(--sg-border)] rounded-lg
               bg-[var(--sg-bg-1)] text-[var(--sg-text)]
               focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-[var(--sg-accent)]
               disabled:opacity-50 disabled:cursor-not-allowed"
        disabled={isSubmitting}
      />
    </div>

    {#if error}
      <div class="bg-[var(--sg-error-bg)] rounded p-3 mb-4 max-w-xl">
        <div class="flex items-start">
          <Icon icon="mdi:alert-circle" class="text-[var(--sg-error)] mr-2 mt-0.5" width="16" />
          <div class="text-sm text-[var(--sg-error)]">{error}</div>
        </div>
      </div>
    {/if}

    {#if submitted}
      <div class="bg-[var(--sg-success-bg)] rounded p-3 mb-4 max-w-xl">
        <div class="flex items-start">
          <Icon icon="mdi:check-circle" class="text-[var(--sg-success)] mr-2 mt-0.5" width="16" />
          <div class="text-sm text-[var(--sg-success)]">
            <strong>Success!</strong> Access token updated.
          </div>
        </div>
      </div>
    {/if}

    <button
      on:click={submit}
      disabled={isSubmitting || !token.trim()}
      class="inline-flex items-center px-6 py-3 font-semibold text-base rounded-lg transition-colors shadow-lg hover:shadow-xl transform hover:-translate-y-0.5 accent-bg disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none disabled:shadow-none"
    >
      {#if isSubmitting}
        <LoadingSpinner size="sm" color="white" centered={false} />
        <span class="ml-2">Submitting...</span>
      {:else}
        <Icon icon="mdi:key-change" class="mr-2" width="20" />
        Update Access Token
      {/if}
    </button>
  </div>
</div>
