<script lang="ts">
  import { Icon } from '../index';

  export let webBaseUrl: string;
  export let groupName: string | null = null;
  export let projectPath: string | null = null;
  export let linkColorClass: string = 'text-[var(--sg-warning)] hover:text-[var(--sg-warning)]';

  $: groupTokensUrl = groupName ? `${webBaseUrl}/groups/${groupName}/-/settings/access_tokens` : null;
  $: projectTokensUrl = projectPath ? `${webBaseUrl}/${projectPath}/-/settings/access_tokens` : null;
  $: personalTokensUrl = `${webBaseUrl}/-/user_settings/personal_access_tokens`;
</script>

<div class="space-y-4 text-sm">
  <div>
    <div class="flex flex-wrap items-center gap-2 mb-1">
      <span class="font-medium text-[var(--sg-text)]">Group access token <span class="text-[var(--sg-text-dim)] font-normal">(recommended)</span></span>
      <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-[var(--sg-purple-bg)] text-[var(--sg-purple)]">
        GitLab Premium or Ultimate
      </span>
    </div>
    <div class="text-[var(--sg-text-muted)]">
      Scoped to this group only and not tied to a person. Available on any tier for self-managed GitLab.
      {#if groupTokensUrl}
        <div class="mt-1">
          <a
            href={groupTokensUrl}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center underline {linkColorClass}"
          >
            Open group access tokens
            <Icon icon="mdi:open-in-new" class="ml-1" width="14" />
          </a>
        </div>
      {/if}
    </div>
  </div>

  <div>
    <div class="flex flex-wrap items-center gap-2 mb-1">
      <span class="font-medium text-[var(--sg-text)]">Project access token</span>
      <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-[var(--sg-purple-bg)] text-[var(--sg-purple)]">
        GitLab Premium or Ultimate
      </span>
    </div>
    <div class="text-[var(--sg-text-muted)]">
      Scoped to a single project. Use only if you're connecting one repo. Available on any tier for self-managed GitLab.
      {#if projectTokensUrl}
        <div class="mt-1">
          <a
            href={projectTokensUrl}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center underline {linkColorClass}"
          >
            Open project access tokens
            <Icon icon="mdi:open-in-new" class="ml-1" width="14" />
          </a>
        </div>
      {/if}
    </div>
  </div>

  <div>
    <div class="font-medium text-[var(--sg-text)] mb-1">Personal access token <span class="text-[var(--sg-text-dim)] font-normal">(fallback)</span></div>
    <div class="text-[var(--sg-text-muted)]">
      Works on any plan, but tied to your user account &mdash; if you lose access to the group, Terrateam loses access too. Use the classic (non-fine-grained) form so you can grant the <strong>api</strong> scope; fine-grained tokens are in beta and don't have an equivalent.
      <div class="mt-1">
        <a
          href={personalTokensUrl}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center underline {linkColorClass}"
        >
          Open personal access tokens
          <Icon icon="mdi:open-in-new" class="ml-1" width="14" />
        </a>
      </div>
    </div>
  </div>

  <div class="pt-2 border-t border-[var(--sg-border)]">
    <div class="text-[var(--sg-text-muted)]">
      Whichever you pick, the token needs the <strong>api</strong> scope. Group and project tokens also need at least the <strong>Developer</strong> role &mdash; personal tokens don't have a role selector.
    </div>
  </div>
</div>
