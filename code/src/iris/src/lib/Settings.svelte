<script lang="ts">
  // Auth handled by PageLayout
  import { user, githubUser } from './auth';
  import PageLayout from './components/layout/PageLayout.svelte';
  import { installations, defaultInstallationId, theme, selectedInstallation, currentVCSProvider } from './stores';
  import type { ThemeMode, ServerConfig } from './types';
  import { api } from './api';
  import Card from './components/ui/Card.svelte';
  import LoadingSpinner from './components/ui/LoadingSpinner.svelte';
  import { VCS_PROVIDERS } from './vcs/providers';
  import AccessTokenSection from './components/settings/AccessTokenSection.svelte';
  import GitLabAccessTokenSection from './components/settings/GitLabAccessTokenSection.svelte';

  // Tab management
  type SettingsTab = 'organization' | 'api-keys' | 'diagnostics';
  let activeTab: SettingsTab = 'organization';

  // Parse URL hash for initial tab
  const urlParams = new URLSearchParams(window.location.hash.split('?')[1] || '');
  const tabParam = urlParams.get('tab');
  if (tabParam === 'api-keys' || tabParam === 'diagnostics' || tabParam === 'organization') {
    activeTab = tabParam;
  }

  // Update URL when tab changes
  function setActiveTab(tab: SettingsTab): void {
    activeTab = tab;
    const currentHash = window.location.hash.split('?')[0];
    const newUrl = `${currentHash}?tab=${tab}`;
    window.history.replaceState({}, '', newUrl);
  }

  let selectedDefaultInstallation: string | null = $defaultInstallationId;
  let selectedTheme: ThemeMode = $theme;
  
  // Get current VCS provider terminology
  $: currentProvider = $currentVCSProvider || 'github';
  $: terminology = VCS_PROVIDERS[currentProvider]?.terminology || VCS_PROVIDERS.github.terminology;

  // Helper functions for proper capitalization and articles
  $: capitalizedOrganization = terminology.organization.charAt(0).toUpperCase() + terminology.organization.slice(1);
  $: articleForOrganization = terminology.organization.match(/^[aeiou]/i) ? 'an' : 'a';

  // Connection diagnostics state
  let serverConfig: ServerConfig | null = null;
  let isLoadingDiagnostics = false;
  let diagnosticsError: string | null = null;
  let lastDiagnosticsCheck: Date | null = null;

  function handleSaveSettings(): void {
    defaultInstallationId.set(selectedDefaultInstallation);
    localStorage.setItem('defaultInstallationId', selectedDefaultInstallation || '');
    
    theme.setTheme(selectedTheme);
    
    // Show success message briefly
    const successEl = document.getElementById('success-message');
    if (successEl) {
      successEl.classList.add('block');
      successEl.classList.remove('hidden');
      setTimeout(() => {
        successEl.classList.remove('block');
        successEl.classList.add('hidden');
      }, 3000);
    }
  }

  async function runDiagnostics(): Promise<void> {
    isLoadingDiagnostics = true;
    diagnosticsError = null;
    
    try {
      // Get server configuration
      serverConfig = await api.getServerConfig();
      lastDiagnosticsCheck = new Date();
    } catch (err) {
      console.error('Diagnostics failed:', err);
      diagnosticsError = err instanceof Error ? err.message : 'Failed to run diagnostics';
      serverConfig = null;
    } finally {
      isLoadingDiagnostics = false;
    }
  }

  // Auto-run diagnostics on component mount
  import { onMount } from 'svelte';
  onMount(() => {
    runDiagnostics();
  });
</script>

<PageLayout activeItem="settings" title="Settings">
    <main class="flex-1 p-6">
      <div class="max-w-4xl mx-auto">
        <!-- Success Message (hidden by default) -->
        <div id="success-message" class="mb-6 bg-[var(--sg-success-bg)] border border-[var(--sg-success)] rounded-lg p-4 hidden">
          <div class="flex items-center">
            <svg class="w-5 h-5 text-[var(--sg-success)] mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <p class="text-[var(--sg-success)] font-medium">Settings saved successfully!</p>
          </div>
        </div>

        <!-- Tab Navigation -->
        <div class="mb-6 border-b border-[var(--sg-border)]">
          <nav class="-mb-px flex space-x-8" aria-label="Settings tabs">
            <button
              on:click={() => setActiveTab('organization')}
              class="whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm transition-colors
                {activeTab === 'organization'
                  ? 'border-[var(--sg-accent)] text-[var(--sg-accent)]'
                  : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:border-[var(--sg-border)]'
                }"
              aria-current={activeTab === 'organization' ? 'page' : undefined}
            >
              <svg class="w-5 h-5 inline-block mr-2 -mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
              Organization Settings
            </button>
            <button
              on:click={() => setActiveTab('api-keys')}
              class="whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm transition-colors
                {activeTab === 'api-keys'
                  ? 'border-[var(--sg-accent)] text-[var(--sg-accent)]'
                  : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:border-[var(--sg-border)]'
                }"
              aria-current={activeTab === 'api-keys' ? 'page' : undefined}
            >
              <svg class="w-5 h-5 inline-block mr-2 -mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z" />
              </svg>
              API Keys
            </button>
            <button
              on:click={() => setActiveTab('diagnostics')}
              class="whitespace-nowrap pb-4 px-1 border-b-2 font-medium text-sm transition-colors
                {activeTab === 'diagnostics'
                  ? 'border-[var(--sg-accent)] text-[var(--sg-accent)]'
                  : 'border-transparent text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] hover:border-[var(--sg-border)]'
                }"
              aria-current={activeTab === 'diagnostics' ? 'page' : undefined}
            >
              <svg class="w-5 h-5 inline-block mr-2 -mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
              Connection Diagnostics
            </button>
          </nav>
        </div>

        <!-- Tab Content -->
        {#if activeTab === 'organization'}
        <!-- {terminology.organization} Settings Card -->
        <div class="card-bg rounded-lg shadow border mb-6">
          <div class="px-4 py-6 md:px-6 md:py-8">
            <!-- Settings Icon -->
            <div class="inline-flex items-center justify-center w-16 h-16 rounded-full mb-6 brand-icon-bg">
              <svg class="w-8 h-8 brand-icon-color" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
            
            <h2 class="text-2xl font-bold text-[var(--sg-text)] mb-6">{capitalizedOrganization} Settings</h2>
            
            <!-- Default {terminology.organization} Selection -->
            <div class="mb-8">
              <label for="default-{terminology.organization.toLowerCase()}" class="block text-sm font-medium text-[var(--sg-text-muted)] mb-3">
                Default {terminology.organization}
              </label>
              <p class="text-sm text-[var(--sg-text-muted)] mb-4">
                Select which {terminology.organization.toLowerCase()} should be selected by default when you login. This helps streamline your workflow by automatically switching to your preferred {terminology.organization.toLowerCase()}.
              </p>
              <select
                id="default-{terminology.organization.toLowerCase()}"
                bind:value={selectedDefaultInstallation}
                class="w-full max-w-md px-3 py-2 border border-[var(--sg-border)] rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)] focus:border-[var(--sg-accent)] bg-[var(--sg-bg-1)] text-[var(--sg-text)]"
              >
                <option value="">Select {articleForOrganization} {terminology.organization.toLowerCase()}...</option>
                {#each $installations as installation}
                  <option value={installation.id}>{installation.name}</option>
                {/each}
              </select>
            </div>

            <!-- Theme Selection -->
            <div class="mb-8">
              <label for="theme-selection" class="block text-sm font-medium text-[var(--sg-text-muted)] mb-3">
                Theme Appearance
              </label>
              <p class="text-sm text-[var(--sg-text-muted)] mb-4">
                Choose how the interface should appear. System default will automatically match your operating system's theme preference.
              </p>
              <div class="space-y-3">
                <label class="flex items-center">
                  <input
                    type="radio"
                    bind:group={selectedTheme}
                    value="system"
                    class="h-4 w-4 text-[var(--sg-accent)] border-[var(--sg-border)] focus:ring-[var(--sg-accent)]"
                  />
                  <span class="ml-3 text-sm text-[var(--sg-text)]">
                    <span class="font-medium">System default</span>
                    <span class="block text-[var(--sg-text-muted)]">Automatically match your device's theme</span>
                  </span>
                </label>
                <label class="flex items-center">
                  <input
                    type="radio"
                    bind:group={selectedTheme}
                    value="light"
                    class="h-4 w-4 text-[var(--sg-accent)] border-[var(--sg-border)] focus:ring-[var(--sg-accent)]"
                  />
                  <span class="ml-3 text-sm text-[var(--sg-text)]">
                    <span class="font-medium">Light mode</span>
                    <span class="block text-[var(--sg-text-muted)]">Use the light theme</span>
                  </span>
                </label>
                <label class="flex items-center">
                  <input
                    type="radio"
                    bind:group={selectedTheme}
                    value="dark"
                    class="h-4 w-4 text-[var(--sg-accent)] border-[var(--sg-border)] focus:ring-[var(--sg-accent)]"
                  />
                  <span class="ml-3 text-sm text-[var(--sg-text)]">
                    <span class="font-medium">Dark mode</span>
                    <span class="block text-[var(--sg-text-muted)]">Use the dark theme</span>
                  </span>
                </label>
              </div>
            </div>

            <!-- Save Button -->
            <button
              on:click={handleSaveSettings}
              class="inline-flex items-center px-6 py-3 font-semibold text-base rounded-lg transition-colors shadow-lg hover:shadow-xl transform hover:-translate-y-0.5 accent-bg"
            >
              <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4" />
              </svg>
              Save Settings
            </button>
          </div>
        </div>

        {#if currentProvider === 'gitlab' && $selectedInstallation}
          <GitLabAccessTokenSection installation={$selectedInstallation} {serverConfig} />
        {/if}

        <!-- Settings Information -->
        <div class="bg-[var(--sg-bg-2)] rounded-lg p-4 md:p-6 border border-[var(--sg-border-light)]">
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <svg class="w-5 h-5 md:w-6 md:h-6 brand-icon-color" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <div class="ml-3 md:ml-4">
              <h3 class="text-base md:text-lg font-semibold text-[var(--sg-text)] mb-2">About Default {capitalizedOrganization}</h3>
              <p class="text-sm md:text-base text-[var(--sg-text-muted)]">
                When you set a default {terminology.organization.toLowerCase()}, it will be automatically selected when you log in or refresh the application.
                You can still switch between {terminology.organizations.toLowerCase()} at any time using the dropdown in the sidebar.
                Your preference is saved locally in your browser.
              </p>
            </div>
          </div>
        </div>

        {:else if activeTab === 'api-keys'}
        <!-- API Keys Tab -->
        <AccessTokenSection />

        {:else if activeTab === 'diagnostics'}
        <!-- Connection Diagnostics Card -->
        <Card padding="md" class="mb-6">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
            <div class="flex items-center">
              <div class="inline-flex items-center justify-center w-10 h-10 md:w-12 md:h-12 rounded-lg mr-3 md:mr-4 brand-icon-bg">
                <svg class="w-6 h-6 brand-icon-color" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
              </div>
              <div>
                <h2 class="text-lg md:text-xl font-bold text-[var(--sg-text)]">Connection Diagnostics</h2>
                <p class="text-xs md:text-sm text-[var(--sg-text-dim)]">
                  {VCS_PROVIDERS[currentProvider].displayName} integration status and API connectivity
                </p>
              </div>
            </div>
            <button
              on:click={runDiagnostics}
              disabled={isLoadingDiagnostics}
              class="inline-flex items-center px-3 py-2 text-sm font-medium rounded-md transition-colors
                {isLoadingDiagnostics 
                  ? 'bg-[var(--sg-bg-2)] text-[var(--sg-text-dim)] cursor-not-allowed' 
                  : 'bg-[var(--sg-bg-1)] text-[var(--sg-text-muted)] border border-[var(--sg-border)] hover:bg-[var(--sg-bg-2)] focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)]'}"
            >
              {#if isLoadingDiagnostics}
                <svg class="animate-spin -ml-0.5 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Checking...
              {:else}
                <svg class="-ml-0.5 mr-2 h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                </svg>
                Refresh
              {/if}
            </button>
          </div>

          {#if isLoadingDiagnostics}
            <div class="flex justify-center items-center py-8">
              <LoadingSpinner size="md" />
              <span class="ml-3 text-[var(--sg-text-dim)]">Running diagnostics...</span>
            </div>
          {:else if diagnosticsError}
            <div class="bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-lg p-4">
              <div class="flex items-center">
                <svg class="w-5 h-5 text-[var(--sg-error)] mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                <div>
                  <p class="font-medium text-[var(--sg-error)]">Connection Failed</p>
                  <p class="text-sm text-[var(--sg-error)]">{diagnosticsError}</p>
                </div>
              </div>
            </div>
          {:else if serverConfig}
            <div class="space-y-4">
              <!-- Overall Status -->
              <div class="bg-[var(--sg-success-bg)] border border-[var(--sg-success)] rounded-lg p-4">
                <div class="flex items-center">
                  <svg class="w-5 h-5 text-[var(--sg-success)] mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <div>
                    <p class="font-medium text-[var(--sg-success)]">All Systems Operational</p>
                    <p class="text-sm text-[var(--sg-success)]">Successfully connected to Terrateam services</p>
                  </div>
                </div>
              </div>

              <!-- Integration Details -->
              <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
                <!-- User Authentication -->
                <div class="bg-[var(--sg-bg-0)] rounded-lg p-4">
                  <div class="flex items-start justify-between mb-3">
                    <h4 class="font-medium text-[var(--sg-text)]">User Authentication</h4>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)] whitespace-nowrap ml-2">
                      Connected
                    </span>
                  </div>
                  <div class="space-y-2 text-xs md:text-sm text-[var(--sg-text-dim)]">
                    <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                      <span class="whitespace-nowrap">User ID:</span>
                      <span class="font-mono truncate">{$user?.id?.substring(0, 8)}...</span>
                    </div>
                    <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                      <span class="whitespace-nowrap">{VCS_PROVIDERS[currentProvider].displayName} User:</span>
                      <span class="truncate">{$githubUser?.username || 'Unknown'}</span>
                    </div>
                  </div>
                </div>

                <!-- Provider Integration -->
                {#if serverConfig.github && currentProvider === 'github'}
                  <div class="bg-[var(--sg-bg-0)] rounded-lg p-4">
                    <div class="flex items-start justify-between mb-3">
                      <h4 class="font-medium text-[var(--sg-text)]">GitHub Integration</h4>
                      <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)] whitespace-nowrap ml-2">
                        Active
                      </span>
                    </div>
                    <div class="space-y-2 text-xs md:text-sm text-[var(--sg-text-dim)]">
                      <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                        <span class="whitespace-nowrap">App Client ID:</span>
                        <span class="font-mono truncate text-xs">{serverConfig.github.app_client_id}</span>
                      </div>
                      <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                        <span class="whitespace-nowrap">API Base:</span>
                        <span class="font-mono truncate text-xs break-all">{serverConfig.github.api_base_url}</span>
                      </div>
                    </div>
                  </div>
                {:else if serverConfig.gitlab && currentProvider === 'gitlab'}
                  <div class="bg-[var(--sg-bg-0)] rounded-lg p-4">
                    <div class="flex items-start justify-between mb-3">
                      <h4 class="font-medium text-[var(--sg-text)]">GitLab Integration</h4>
                      <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)] whitespace-nowrap ml-2">
                        Active
                      </span>
                    </div>
                    <div class="space-y-2 text-xs md:text-sm text-[var(--sg-text-dim)]">
                      <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                        <span class="whitespace-nowrap">App ID:</span>
                        <span class="font-mono truncate text-xs">{serverConfig.gitlab.app_id.length > 12 ? serverConfig.gitlab.app_id.substring(0, 12) + '...' : serverConfig.gitlab.app_id}</span>
                      </div>
                      <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                        <span class="whitespace-nowrap">API Base:</span>
                        <span class="font-mono truncate text-xs break-all">{serverConfig.gitlab.api_base_url.length > 20 ? serverConfig.gitlab.api_base_url.substring(0, 20) + '...' : serverConfig.gitlab.api_base_url}</span>
                      </div>
                      <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                        <span class="whitespace-nowrap">Web Base:</span>
                        <span class="font-mono truncate text-xs break-all">{serverConfig.gitlab.web_base_url.length > 20 ? serverConfig.gitlab.web_base_url.substring(0, 20) + '...' : serverConfig.gitlab.web_base_url}</span>
                      </div>
                    </div>
                  </div>
                {:else}
                  <div class="bg-[var(--sg-bg-0)] rounded-lg p-4">
                    <div class="flex items-start justify-between mb-3">
                      <h4 class="font-medium text-[var(--sg-text)]">{VCS_PROVIDERS[currentProvider].displayName} Integration</h4>
                      <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-warning-bg)] text-[var(--sg-warning)] whitespace-nowrap ml-2">
                        Not Configured
                      </span>
                    </div>
                    <div class="text-sm text-[var(--sg-text-dim)]">
                      Server configuration not available for {VCS_PROVIDERS[currentProvider].displayName}
                    </div>
                  </div>
                {/if}

                <!-- {terminology.organizations} -->
                <div class="bg-[var(--sg-bg-0)] rounded-lg p-4">
                  <div class="flex items-start justify-between mb-3">
                    <h4 class="font-medium text-[var(--sg-text)]">{terminology.organizations}</h4>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] whitespace-nowrap ml-2">
                      {$installations.length} Connected
                    </span>
                  </div>
                  <div class="space-y-1 text-xs md:text-sm text-[var(--sg-text-dim)]">
                    {#each $installations.slice(0, 3) as installation}
                      <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                        <span class="truncate">{installation.name}</span>
                        <span class="text-xs text-[var(--sg-text-dim)]">{installation.tier?.name || 'Free'}</span>
                      </div>
                    {/each}
                    {#if $installations.length > 3}
                      <div class="text-xs text-[var(--sg-text-dim)]">
                        +{$installations.length - 3} more {terminology.organizations.toLowerCase()}
                      </div>
                    {/if}
                  </div>
                </div>

                <!-- Current Session -->
                <div class="bg-[var(--sg-bg-0)] rounded-lg p-4">
                  <div class="flex items-start justify-between mb-3">
                    <h4 class="font-medium text-[var(--sg-text)]">Current Session</h4>
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-[var(--sg-success-bg)] text-[var(--sg-success)] whitespace-nowrap ml-2">
                      Active
                    </span>
                  </div>
                  <div class="space-y-2 text-xs md:text-sm text-[var(--sg-text-dim)]">
                    <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                      <span class="whitespace-nowrap">Selected Org:</span>
                      <span class="truncate">{$selectedInstallation?.name || 'None'}</span>
                    </div>
                    <div class="flex flex-col sm:flex-row sm:justify-between gap-1">
                      <span class="whitespace-nowrap">Last Check:</span>
                      <span class="truncate">{lastDiagnosticsCheck ? new Intl.DateTimeFormat('en-US', { 
                        hour: '2-digit', 
                        minute: '2-digit',
                        second: '2-digit'
                      }).format(lastDiagnosticsCheck) : 'Never'}</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          {/if}
        </Card>
        {/if}
        <!-- End of tab content -->
      </div>
    </main>
</PageLayout>