<script lang="ts">
  // Auth handled by PageLayout
  import PageLayout from './components/layout/PageLayout.svelte';
  import { selectedInstallation, installations, currentVCSProvider } from './stores';
  import { Icon } from './components';
  import hljs from 'highlight.js/lib/core';
  import yamlLang from 'highlight.js/lib/languages/yaml';
  import 'highlight.js/styles/github-dark.css';
  
  // Import our configuration engine
  import { generateConfig, getSecretsForProvider, CONFIG_PRESETS, type ConfigBuilderOptions } from './ConfigurationEngine';
  import { EXTERNAL_URLS } from './constants';
  
  // Register YAML language
  hljs.registerLanguage('yaml', yamlLang);
  
  export let params: { installationId?: string } = {};

  // UI state
  let selectedMode: 'wizard' | 'custom' = 'wizard';
  let selectedPreset: keyof typeof CONFIG_PRESETS | null = null;
  
  // Config builder state - initialized from preset or empty
  let configOptions: ConfigBuilderOptions = { ...CONFIG_PRESETS.starter.options };
  
  // Generated config state
  let generatedConfig: string = '';
  let highlightedConfig: string = '';
  let copySuccess: boolean = false;
  let showToast: boolean = false;
  
  // Feature categories for organized display
  const featureCategories: Record<string, { name: string; icon: string; iconName: string; features: FeatureKey[] }> = {
    automation: {
      name: 'Automation & Workflows',
      icon: 'mdi:robot-outline',
      iconName: 'mdi:robot-outline',
      features: ['automerge', 'applyAfterMerge', 'applyRequirements', 'layeredRuns']
    },
    security: {
      name: 'Security & Compliance',
      icon: 'mdi:shield-check-outline',
      iconName: 'mdi:shield-check-outline',
      features: ['rbac', 'opa']
    },
    monitoring: {
      name: 'Monitoring & Insights',
      icon: 'mdi:chart-line',
      iconName: 'mdi:chart-line',
      features: ['costEstimation', 'driftDetection', 'slackNotifications']
    },
    advanced: {
      name: 'Advanced Patterns',
      icon: 'mdi:puzzle-outline',
      iconName: 'mdi:puzzle-outline',
      features: ['gitflow']
    }
  };

  // Auto-switch to static auth when Azure is selected (OIDC not supported yet)
  $: if (configOptions.provider === 'azure' && configOptions.authMethod === 'oidc') {
    configOptions = { ...configOptions, authMethod: 'static' };
  }

  // Generate config whenever options change
  $: generatedConfig = generateConfig(configOptions);
  
  // Highlight the YAML configuration whenever it changes
  $: if (generatedConfig) {
    if (generatedConfig.includes('No configuration file is required')) {
      // For the "no config needed" message, don't highlight
      highlightedConfig = generatedConfig;
    } else {
      // Highlight YAML syntax
      highlightedConfig = hljs.highlight(generatedConfig, { language: 'yaml' }).value;
    }
  }

  // When preset is selected, update config options
  function selectPreset(preset: keyof typeof CONFIG_PRESETS) {
    selectedPreset = preset;
    configOptions = { ...CONFIG_PRESETS[preset].options };
  }
  
  // Type helper for feature keys
  type FeatureKey = keyof Pick<ConfigBuilderOptions, 
    'costEstimation' | 'driftDetection' | 'automerge' | 'applyAfterMerge' | 
    'applyRequirements' | 'slackNotifications' | 'rbac' | 'layeredRuns' | 
    'gitflow' | 'opa'>;
  
  // Helper to select preset by string key
  function selectPresetByKey(key: string) {
    selectPreset(key as keyof typeof CONFIG_PRESETS);
  }
  
  // Helper to toggle feature
  function toggleFeature(feature: string) {
    const key = feature as FeatureKey;
    const oldValue = configOptions[key];
    const newValue = !oldValue;
    configOptions = { ...configOptions, [key]: newValue };
  }
  
  // Helper to check if feature is enabled
  // function isFeatureEnabled(feature: string): boolean {
  //   const isEnabled = configOptions[feature as FeatureKey];
  //   return isEnabled;
  // }
  
  // Helper to set provider
  function setProvider(provider: string) {
    configOptions = { ...configOptions, provider: provider as 'none' | 'aws' | 'gcp' | 'azure' };
    // For starter preset, always use static secrets
    if (selectedPreset === 'starter' && provider !== 'none') {
      configOptions = { ...configOptions, authMethod: 'static' };
    }
  }
  
  // Helper to set repo structure
  function setRepoStructure(structure: string) {
    configOptions = { ...configOptions, repoStructure: structure as 'directories' | 'tfvars' | 'workspaces' };
  }

  // Switch to custom mode
  function switchToCustom() {
    selectedMode = 'custom';
    // Keep current config options
  }

  async function copyToClipboard() {
    try {
      await navigator.clipboard.writeText(generatedConfig);
      copySuccess = true;
      showToast = true;
      
      // Reset the button state after 2 seconds
      setTimeout(() => {
        copySuccess = false;
      }, 2000);
      
      // Hide toast after 3 seconds
      setTimeout(() => {
        showToast = false;
      }, 3000);
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  }

  function openDocumentation(url: string): void {
    window.open(url, '_blank');
  }

  // Auto-select installation if provided in URL
  $: if (params.installationId && $installations && $installations.length > 0) {
    const targetInstallation = $installations.find(inst => inst.id === params.installationId);
    if (targetInstallation && (!$selectedInstallation || $selectedInstallation.id !== targetInstallation.id)) {
      selectedInstallation.set(targetInstallation);
    }
  }

  // Feature info for tooltips
  const featureInfo: Record<FeatureKey, { name: string; description: string; docUrl: string }> = {
    costEstimation: { 
      name: 'Cost Estimation', 
      description: 'See cost impact before applying changes',
      docUrl: 'https://docs.terrateam.io/configuration-reference/cost-estimation/'
    },
    driftDetection: { 
      name: 'Drift Detection', 
      description: 'Detect unauthorized infrastructure changes',
      docUrl: 'https://docs.terrateam.io/advanced-workflows/drift-detection/'
    },
    automerge: { 
      name: 'Auto-merge', 
      description: 'Automatically merge PRs after successful apply',
      docUrl: 'https://docs.terrateam.io/configuration-reference/automerge/'
    },
    applyAfterMerge: { 
      name: 'Apply After Merge', 
      description: 'Automatically apply changes when PR is merged',
      docUrl: 'https://docs.terrateam.io/configuration-reference/apply-requirements/#apply-after-merge'
    },
    applyRequirements: { 
      name: 'Apply Requirements', 
      description: 'Require approvals before applying changes',
      docUrl: 'https://docs.terrateam.io/configuration-reference/apply-requirements/'
    },
    slackNotifications: { 
      name: 'Slack Notifications', 
      description: 'Send run updates to Slack',
      docUrl: 'https://docs.terrateam.io/integrations/webhooks/#slack-notifications'
    },
    rbac: { 
      name: 'Role-Based Access', 
      description: 'Control who can plan/apply by team or user',
      docUrl: 'https://docs.terrateam.io/security-and-compliance/role-based-access-control/'
    },
    layeredRuns: { 
      name: 'Layered Runs', 
      description: 'Run infrastructure in dependency order',
      docUrl: 'https://docs.terrateam.io/advanced-workflows/layered-runs/'
    },
    gitflow: { 
      name: 'Gitflow Workflow', 
      description: 'Structured branching with main/dev/feature',
      docUrl: 'https://docs.terrateam.io/advanced-workflows/gitflow/'
    },
    opa: { 
      name: 'Policy Checks', 
      description: 'Enforce policies with Open Policy Agent',
      docUrl: 'https://docs.terrateam.io/security-and-compliance/policy-enforcement-with-opa/'
    }
  };
</script>

<PageLayout activeItem="configuration" title="Terrateam Configuration" subtitle="Generate and customize your Terrateam configuration">
  <div class="h-full flex flex-col">
    
    <!-- Mode Selection -->
    {#if selectedMode === 'wizard' && !selectedPreset}
      <!-- Preset Selection Screen -->
      <div class="max-w-7xl mx-auto w-full px-2 sm:px-4">
        <div class="mb-6 sm:mb-8 text-center">
          <h2 class="text-2xl sm:text-3xl font-bold text-[var(--sg-text)] mb-2 sm:mb-3">Choose Your Configuration Path</h2>
          <p class="text-base sm:text-lg text-[var(--sg-text-dim)] mb-2">Select a template to get started quickly, or build a custom configuration</p>
          <p class="text-sm text-[var(--sg-text-dim)] flex items-center justify-center gap-2">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 15l-2 5L9 9l11 4-5 2zm0 0l5 5M7.188 2.239l1.416 7.041m3.23 3.23l7.042 1.416M10.83 13.17l-7.041 1.416l7.04 1.414z" />
            </svg>
            Click any option below to generate your configuration
          </p>
        </div>

        <!-- Free Onboarding Support Banner -->
        <div class="mb-6 sm:mb-8 bg-[var(--sg-accent-bg)] rounded-xl p-5 sm:p-6 border border-[var(--sg-accent)]">
          <div class="flex flex-col items-center text-center gap-4">
            <div class="w-14 h-14 bg-[var(--sg-accent-bg)] rounded-full flex items-center justify-center">
              <Icon icon="mdi:slack" width="28" height="28" class="text-[var(--sg-accent)]" />
            </div>
            <div class="max-w-lg">
              <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)] mb-2">Need help getting started?</h3>
              <p class="text-sm sm:text-base text-[var(--sg-text-dim)] leading-relaxed">
                Join our <span class="font-semibold text-[var(--sg-accent)]">Slack community</span> to get instant help from Terrateam engineers and connect with other users.
              </p>
            </div>
            <button
              on:click={() => window.open(EXTERNAL_URLS.SLACK, '_blank')}
              class="w-full sm:w-auto inline-flex items-center justify-center px-6 py-3 bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white font-medium text-sm sm:text-base rounded-lg transition-all duration-200 shadow-md hover:shadow-lg transform hover:-translate-y-0.5"
            >
              <Icon icon="mdi:slack" width="20" height="20" class="mr-2" />
              Join Slack Community
            </button>
          </div>
        </div>

        <!-- Preset Cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 sm:gap-6 mb-6 sm:mb-8">
          {#each Object.entries(CONFIG_PRESETS) as [key, preset]}
            <button
              on:click={() => selectPresetByKey(key)}
              class="relative bg-[var(--sg-bg-1)] rounded-xl border-2 border-[var(--sg-border)] p-4 sm:p-6 text-left hover:border-[var(--sg-accent)] hover:shadow-xl hover:-translate-y-1 transition-all duration-200 group cursor-pointer overflow-hidden h-full flex flex-col"
            >
              <!-- Hover gradient overlay -->
              <div class="absolute inset-0 bg-gradient-to-br from-[var(--sg-accent)]/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-200"></div>
              
              <!-- Click to select badge -->
              <div class="absolute top-3 right-3 bg-[var(--sg-accent-button)] text-white text-xs px-2 py-1 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200 flex items-center gap-1">
                <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 15l-2 5L9 9l11 4-5 2z" />
                </svg>
                Click to select
              </div>
              
              <!-- Card content -->
              <div class="relative flex-1 flex flex-col">
                <div class="mb-4 transform group-hover:scale-110 transition-transform duration-200">
                  <Icon icon={preset.icon} width="32" height="32" class="text-[var(--sg-text-dim)] group-hover:text-[var(--sg-accent)] transition-colors" />
                </div>
                <h3 class="text-lg font-semibold text-[var(--sg-text)] mb-2 group-hover:text-[var(--sg-accent)] transition-colors">
                  {preset.name}
                </h3>
                <p class="text-sm text-[var(--sg-text-dim)] mb-4">{preset.description}</p>
                
                <!-- Feature highlights -->
                <div class="pt-4 border-t border-[var(--sg-border)]">
                  {#if key === 'starter'}
                    <div class="text-xs text-[var(--sg-success)] font-medium">
                      ✓ Choose your provider<br>
                      ✓ Minimal configuration<br>
                      ✓ Add features later
                    </div>
                    <div class="mt-3 text-xs text-[var(--sg-text-dim)]">
                      <strong>Best for:</strong> Getting started quickly
                    </div>
                  {:else if key === 'team'}
                    <div class="text-xs text-[var(--sg-accent)] font-medium">
                      ✓ Cost tracking<br>
                      ✓ Access controls<br>
                      ✓ Slack notifications
                    </div>
                    <div class="mt-3 text-xs text-[var(--sg-text-dim)]">
                      <strong>Best for:</strong> Small teams
                    </div>
                  {:else if key === 'advanced'}
                    <div class="text-xs text-[var(--sg-purple)] font-medium">
                      ✓ OIDC authentication<br>
                      ✓ Policy enforcement<br>
                      ✓ Full governance
                    </div>
                    <div class="mt-3 text-xs text-[var(--sg-text-dim)]">
                      <strong>Best for:</strong> Large organizations
                    </div>
                  {/if}
                </div>
                
                <!-- Action Button -->
                <div class="mt-4 pt-4 border-t border-[var(--sg-border)]">
                  <div class="flex items-center justify-between">
                    <span class="text-xs font-medium text-[var(--sg-accent)] group-hover:text-[var(--sg-accent)]">Generate Config</span>
                    <svg class="w-4 h-4 text-[var(--sg-accent)] group-hover:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6" />
                    </svg>
                  </div>
                </div>
              </div>
            </button>
          {/each}
          
          <!-- Custom Configuration Card -->
          <button
            on:click={switchToCustom}
            class="relative bg-[var(--sg-bg-1)] rounded-xl border-2 border-[var(--sg-border)] p-4 sm:p-6 text-left hover:border-[var(--sg-purple)] hover:shadow-xl hover:-translate-y-1 transition-all duration-200 group cursor-pointer overflow-hidden h-full flex flex-col"
          >
            <!-- Hover gradient overlay -->
            <div class="absolute inset-0 bg-gradient-to-br from-[var(--sg-purple)]/5 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-200"></div>
            
            <!-- Click to select badge -->
            <div class="absolute top-3 right-3 bg-[var(--sg-purple)] text-white text-xs px-2 py-1 rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200 flex items-center gap-1">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 15l-2 5L9 9l11 4-5 2z" />
              </svg>
              Click to build
            </div>
            
            <!-- Card content -->
            <div class="relative flex-1 flex flex-col">
              <div class="mb-4 transform group-hover:scale-110 transition-transform duration-200">
                <Icon icon="mdi:tools" width="32" height="32" class="text-[var(--sg-text-dim)] group-hover:text-[var(--sg-purple)] transition-colors" />
              </div>
              <h3 class="text-lg font-semibold text-[var(--sg-text)] mb-2 group-hover:text-[var(--sg-purple)] transition-colors">
                Custom
              </h3>
              <p class="text-sm text-[var(--sg-text-dim)] mb-4">Build your configuration from scratch</p>
              
              <div class="pt-4 border-t border-[var(--sg-border)]">
                <div class="text-xs text-[var(--sg-purple)] font-medium">
                  ✓ Full control<br>
                  ✓ Mix & match features<br>
                  ✓ Advanced options
                </div>
                <div class="mt-3 text-xs text-[var(--sg-text-dim)]">
                  <strong>Best for:</strong> Specific requirements
                </div>
              </div>
              
              <!-- Action Button -->
              <div class="mt-4 pt-4 border-t border-[var(--sg-border)]">
                <div class="flex items-center justify-between">
                  <span class="text-xs font-medium text-[var(--sg-purple)] group-hover:opacity-90">Build Custom Config</span>
                  <svg class="w-4 h-4 text-[var(--sg-purple)] group-hover:translate-x-1 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6" />
                  </svg>
                </div>
              </div>
            </div>
          </button>
        </div>

        <!-- Two column layout: Guide and Comparison -->
        <div class="grid grid-cols-1 xl:grid-cols-5 gap-6 mt-8">
          <!-- Left column: Visual guide -->
          <div class="xl:col-span-2 bg-[var(--sg-bg-0)] rounded-xl p-4 sm:p-6 border border-[var(--sg-border)]">
            <h3 class="text-base sm:text-sm font-semibold text-[var(--sg-text)] mb-4 flex items-center">
              <Icon icon="mdi:book-open-variant" width="20" height="20" class="mr-2 text-[var(--sg-text-dim)]" />
              How it Works
            </h3>
            
            <!-- Repository structure -->
            <div class="mb-6">
              <h4 class="text-xs font-medium text-[var(--sg-text-muted)] mb-3 uppercase tracking-wider">Repository Structure</h4>
              <div class="bg-[var(--sg-bg-1)] rounded-lg p-3 sm:p-4 border border-[var(--sg-border)] font-mono text-xs overflow-x-auto">
                <div class="flex items-center text-[var(--sg-text-muted)] mb-1">
                  <Icon icon="mdi:github" width="16" height="16" class="mr-2" />
                  <span class="font-semibold">my-terraform-repo</span>
                </div>
                <div class="border-l-2 border-[var(--sg-border)] ml-2 pl-3">
                  <div class="flex items-center text-[var(--sg-text-dim)]">
                    <Icon icon="mdi:folder" width="16" height="16" class="mr-2" />
                    <span>.terrateam/</span>
                  </div>
                  <div class="ml-4 mt-1">
                    <div class="flex flex-col sm:flex-row sm:items-center gap-1">
                      <div class="flex items-center text-[var(--sg-success)] font-semibold">
                        <Icon icon="mdi:file-code" width="16" height="16" class="mr-2" />
                        <span>config.yml</span>
                      </div>
                      <span class="ml-6 sm:ml-2 text-xs font-normal text-[var(--sg-text-dim)]">← Your config</span>
                    </div>
                  </div>
                  <div class="flex items-center text-[var(--sg-text-dim)] mt-1">
                    <Icon icon="mdi:folder" width="16" height="16" class="mr-2" />
                    <span>terraform/</span>
                  </div>
                  <div class="ml-4 mt-1">
                    <div class="flex items-center text-[var(--sg-text-dim)]">
                      <Icon icon="mdi:file" width="16" height="16" class="mr-2" />
                      <span>main.tf</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            
            <!-- Quick steps -->
            <div>
              <h4 class="text-xs font-medium text-[var(--sg-text-muted)] mb-3 uppercase tracking-wider">Quick Steps</h4>
              <ol class="space-y-3 text-sm text-[var(--sg-text-dim)]">
                <li class="flex items-start">
                  <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] text-xs font-semibold mr-2 flex-shrink-0 mt-0.5">1</span>
                  <span>Select a template or build custom</span>
                </li>
                <li class="flex items-start">
                  <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] text-xs font-semibold mr-2 flex-shrink-0 mt-0.5">2</span>
                  <span>Copy generated configuration</span>
                </li>
                <li class="flex items-start">
                  <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] text-xs font-semibold mr-2 flex-shrink-0 mt-0.5">3</span>
                  <span class="break-words">Commit to <code class="bg-[var(--sg-bg-2)] px-1 rounded text-xs whitespace-nowrap">.terrateam/config.yml</code></span>
                </li>
                <li class="flex items-start">
                  <span class="inline-flex items-center justify-center w-5 h-5 rounded-full bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] text-xs font-semibold mr-2 flex-shrink-0 mt-0.5">4</span>
                  <span>Open PR to activate</span>
                </li>
              </ol>
            </div>
          </div>

          <!-- Right column: Available Features -->
          <div class="xl:col-span-3 bg-gradient-to-br bg-[var(--sg-bg-0)] rounded-xl border border-[var(--sg-border)] overflow-hidden shadow-sm">
            <div class="p-5 sm:p-6 border-b border-[var(--sg-border)] bg-[var(--sg-bg-1)] backdrop-blur-sm">
              <h3 class="text-lg sm:text-base font-semibold text-[var(--sg-text)]">Available Features</h3>
              <p class="text-sm sm:text-xs text-[var(--sg-text-dim)] mt-1">All features are included in every Terrateam plan</p>
            </div>
            <div class="p-5 sm:p-6">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 sm:gap-5">
                <!-- Core Features -->
                <div class="bg-[var(--sg-bg-1)]/50 rounded-lg p-4 border border-[var(--sg-border-light)]">
                  <h4 class="text-sm font-semibold text-[var(--sg-text)] mb-3 flex items-center">
                    <Icon icon="mdi:robot-outline" width="18" height="18" class="mr-2 text-[var(--sg-accent)]" />
                    Core Automation
                  </h4>
                  <ul class="space-y-2">
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Automated plan & apply</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Multi-{$currentVCSProvider === 'gitlab' ? 'GitLab environment' : 'GitHub environment'} support</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Directory & workspace management</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>GitOps workflow</span>
                    </li>
                  </ul>
                </div>
                  
                <!-- Monitoring & Insights -->
                <div class="bg-[var(--sg-bg-1)]/50 rounded-lg p-4 border border-[var(--sg-border-light)]">
                  <h4 class="text-sm font-semibold text-[var(--sg-text)] mb-3 flex items-center">
                    <Icon icon="mdi:chart-line" width="18" height="18" class="mr-2 text-[var(--sg-purple)]" />
                    Monitoring & Insights
                  </h4>
                  <ul class="space-y-2">
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Cost estimation</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Drift detection</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Slack notifications</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Detailed logs & metrics</span>
                    </li>
                  </ul>
                </div>
                
                <!-- Security & Compliance -->
                <div class="bg-[var(--sg-bg-1)]/50 rounded-lg p-4 border border-[var(--sg-border-light)]">
                  <h4 class="text-sm font-semibold text-[var(--sg-text)] mb-3 flex items-center">
                    <Icon icon="mdi:shield-check-outline" width="18" height="18" class="mr-2 text-[var(--sg-success)]" />
                    Security & Compliance
                  </h4>
                  <ul class="space-y-2">
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>OIDC authentication</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Role-based access control</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Policy as Code (OPA)</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Private runners</span>
                    </li>
                  </ul>
                </div>
                
                <!-- Advanced Patterns -->
                <div class="bg-[var(--sg-bg-1)]/50 rounded-lg p-4 border border-[var(--sg-border-light)]">
                  <h4 class="text-sm font-semibold text-[var(--sg-text)] mb-3 flex items-center">
                    <Icon icon="mdi:puzzle-outline" width="18" height="18" class="mr-2 text-[var(--sg-warning)]" />
                    Advanced Patterns
                  </h4>
                  <ul class="space-y-2">
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Layered runs</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Automerge</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Apply after merge</span>
                    </li>
                    <li class="text-sm text-[var(--sg-text-dim)] flex items-start">
                      <span class="text-[var(--sg-success)] mr-2 mt-0.5">✓</span>
                      <span>Apply requirements</span>
                    </li>
                  </ul>
                </div>
              </div>
              
              <div class="mt-4 pt-4 border-t border-[var(--sg-border)]">
                <a 
                  href="https://docs.terrateam.io/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-xs text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] font-medium flex items-center"
                >
                  View all features in documentation
                  <Icon icon="mdi:open-in-new" width="14" height="14" class="ml-1" />
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>

    {:else}
      <!-- Configuration Builder (Wizard or Custom) -->
      <div class="mb-6">
        <!-- Breadcrumb / Mode indicator -->
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-6">
          <div class="flex items-center flex-wrap gap-x-2 text-sm">
            <button 
              on:click={() => { selectedMode = 'wizard'; selectedPreset = null; }}
              class="text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)]"
            >
              Configuration
            </button>
            <span class="text-[var(--sg-text-dim)]">/</span>
            <span class="text-[var(--sg-text)] font-medium">
              {#if selectedPreset}
                <span class="inline-block">{CONFIG_PRESETS[selectedPreset].name}</span>
                <span class="hidden sm:inline"> Configuration</span>
              {:else}
                Custom Configuration
              {/if}
            </span>
          </div>
          
          {#if selectedMode === 'wizard' && selectedPreset}
            <button
              on:click={switchToCustom}
              class="text-sm text-[var(--sg-purple)] hover:opacity-90 font-medium whitespace-nowrap"
            >
              Customize Further →
            </button>
          {/if}
        </div>

        {#if selectedMode === 'wizard' && selectedPreset}
          <!-- Wizard Mode with Preset -->
          <div class="bg-[var(--sg-accent-bg)] rounded-xl border border-[var(--sg-accent)] p-4 sm:p-6 mb-6">
            <div class="flex flex-col sm:flex-row sm:items-start gap-4">
              <div class="flex justify-center sm:block">
                <Icon icon={CONFIG_PRESETS[selectedPreset].icon} width="48" height="48" class="text-[var(--sg-accent)]" />
              </div>
              <div class="flex-1 text-center sm:text-left">
                <h3 class="text-lg sm:text-xl font-bold text-[var(--sg-accent)] mb-2">
                  {CONFIG_PRESETS[selectedPreset].name} Configuration
                </h3>
                <p class="text-sm sm:text-base text-[var(--sg-accent)] mb-4">
                  {CONFIG_PRESETS[selectedPreset].description}
                </p>
                
                <!-- Quick customization for all presets -->
                <div class="space-y-4">
                    <!-- Provider selection -->
                    <div>
                      <div class="block text-sm font-medium text-[var(--sg-accent)] mb-3">
                        Cloud Provider
                      </div>
                      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
                        {#each ['none', 'aws', 'gcp', 'azure'] as provider}
                          <button
                            on:click={() => setProvider(provider)}
                            class="p-4 sm:p-3 rounded-lg border-2 transition-all flex flex-col items-center gap-2 {
                              configOptions.provider === provider 
                                ? 'border-[var(--sg-accent)] bg-[var(--sg-accent-bg)] shadow-md' 
                                : 'border-[var(--sg-border)] hover:border-[var(--sg-accent)] bg-[var(--sg-bg-1)]'
                            }"
                          >
                            {#if provider === 'none'}
                              <Icon icon="mdi:wrench-outline" width="28" height="28" class="text-[var(--sg-text-dim)]" />
                              <div class="text-xs font-medium">None</div>
                            {:else if provider === 'aws'}
                              <Icon icon="logos:aws" width="28" height="28" />
                              <div class="text-xs font-medium">AWS</div>
                            {:else if provider === 'gcp'}
                              <Icon icon="logos:google-cloud" width="28" height="28" />
                              <div class="text-xs font-medium">GCP</div>
                            {:else if provider === 'azure'}
                              <Icon icon="logos:microsoft-azure" width="28" height="28" />
                              <div class="text-xs font-medium">Azure</div>
                            {/if}
                          </button>
                        {/each}
                      </div>
                      
                      <!-- Documentation link for starter and team with provider -->
                      {#if (selectedPreset === 'starter' || selectedPreset === 'team') && configOptions.provider !== 'none'}
                        <div class="mt-3 p-3 bg-[var(--sg-accent-bg)] rounded-lg border border-[var(--sg-accent)]">
                          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                            <div class="flex items-start sm:items-center text-xs sm:text-sm text-[var(--sg-accent)]">
                              <Icon icon="mdi:information-outline" width="16" height="16" class="mr-2 flex-shrink-0 mt-0.5 sm:mt-0" />
                              <span>
                                Setup requires adding secrets to your GitHub repository
                              </span>
                            </div>
                            <a 
                              href="https://docs.terrateam.io/cloud-providers/{configOptions.provider}/"
                              target="_blank"
                              rel="noopener noreferrer"
                              class="text-xs sm:text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] flex items-center self-start sm:self-auto whitespace-nowrap"
                              on:click|stopPropagation
                            >
                              View Setup Guide
                              <Icon icon="mdi:open-in-new" width="14" height="14" class="ml-1" />
                            </a>
                          </div>
                        </div>
                      {/if}
                    </div>

                    {#if selectedPreset === 'advanced' && configOptions.provider !== 'none'}
                      <!-- Auth method for advanced -->
                      <div>
                        <div class="block text-sm font-medium text-[var(--sg-accent)] mb-2">
                          Authentication Method
                        </div>
                        <div class="grid grid-cols-2 gap-2">
                          <button
                            on:click={() => configOptions = { ...configOptions, authMethod: 'static' }}
                            class="p-3 rounded-lg border-2 transition-all {
                              configOptions.authMethod === 'static'
                                ? 'border-[var(--sg-accent)] bg-[var(--sg-accent-bg)]'
                                : 'border-[var(--sg-border)] hover:border-[var(--sg-accent)]'
                            }"
                          >
                            <Icon icon="mdi:key-outline" width="24" height="24" class="text-[var(--sg-text-dim)] mb-1" />
                            <div class="text-sm font-medium">Static Secrets</div>
                            <div class="text-xs text-[var(--sg-text-dim)]">Easier setup</div>
                          </button>
                          <button
                            on:click={() => configOptions.provider !== 'azure' && (configOptions = { ...configOptions, authMethod: 'oidc' })}
                            disabled={configOptions.provider === 'azure'}
                            class="p-3 rounded-lg border-2 transition-all {
                              configOptions.provider === 'azure' 
                                ? 'border-[var(--sg-border)] opacity-50 cursor-not-allowed'
                                : configOptions.authMethod === 'oidc'
                                  ? 'border-[var(--sg-accent)] bg-[var(--sg-accent-bg)]'
                                  : 'border-[var(--sg-border)] hover:border-[var(--sg-accent)]'
                            }"
                          >
                            <Icon icon="mdi:shield-lock-outline" width="24" height="24" class="text-[var(--sg-text-dim)] mb-1" />
                            <div class="text-sm font-medium">OIDC</div>
                            <div class="text-xs text-[var(--sg-text-dim)]">
                              {configOptions.provider === 'azure' ? 'Coming soon' : 'More secure'}
                            </div>
                          </button>
                        </div>
                        
                        <!-- Documentation link for selected auth method -->
                        {#if configOptions.authMethod === 'static' || configOptions.authMethod === 'oidc'}
                          <div class="mt-3 p-3 bg-[var(--sg-accent-bg)] rounded-lg border border-[var(--sg-accent)]">
                            <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
                              <div class="flex items-start sm:items-center text-xs sm:text-sm text-[var(--sg-accent)]">
                                <Icon icon="mdi:information-outline" width="16" height="16" class="mr-2 flex-shrink-0 mt-0.5 sm:mt-0" />
                                <span>
                                  {#if configOptions.authMethod === 'static'}
                                    Setup requires adding secrets to your GitHub repository
                                  {:else}
                                    OIDC provides secure, temporary credentials
                                  {/if}
                                </span>
                              </div>
                              <a 
                                href="https://docs.terrateam.io/cloud-providers/{configOptions.provider}/"
                                target="_blank"
                                rel="noopener noreferrer"
                                class="text-xs sm:text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] flex items-center self-start sm:self-auto whitespace-nowrap"
                                on:click|stopPropagation
                              >
                                View Setup Guide
                                <Icon icon="mdi:open-in-new" width="14" height="14" class="ml-1" />
                              </a>
                            </div>
                          </div>
                        {/if}
                      </div>
                    {/if}
                  </div>
              </div>
            </div>
          </div>
        {:else}
          <!-- Custom Mode - Full Configuration -->
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <!-- Left Column: Basic Setup -->
            <div class="space-y-6">
              <div class="bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)] p-6">
                <h3 class="text-lg font-semibold text-[var(--sg-text)] mb-4">Basic Setup</h3>
                
                <!-- Cloud Provider -->
                <div class="mb-4">
                  <div class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
                    Cloud Provider
                  </div>
                  <div class="grid grid-cols-2 gap-2">
                    {#each [
                      { value: 'none', icon: '🔧', name: 'None' },
                      { value: 'aws', icon: 'logos:aws', name: 'AWS' },
                      { value: 'gcp', icon: 'logos:google-cloud', name: 'GCP' },
                      { value: 'azure', icon: 'logos:microsoft-azure', name: 'Azure' }
                    ] as provider}
                      <button
                        on:click={() => setProvider(provider.value)}
                        class="p-3 rounded-lg border-2 transition-all {
                          configOptions.provider === provider.value
                            ? 'border-[var(--sg-accent)] bg-[var(--sg-accent-bg)]'
                            : 'border-[var(--sg-border)] hover:border-[var(--sg-border)]'
                        }"
                      >
                        {#if provider.icon.includes(':')}
                          <Icon icon={provider.icon} width="32" height="32" class="mx-auto mb-1" />
                        {:else}
                          <div class="text-2xl mb-1">{provider.icon}</div>
                        {/if}
                        <div class="text-sm font-medium">{provider.name}</div>
                      </button>
                    {/each}
                  </div>
                </div>

                <!-- Authentication Method -->
                {#if configOptions.provider !== 'none'}
                  <div class="mb-4">
                    <div class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
                      Authentication Method
                    </div>
                    <div class="grid grid-cols-2 gap-2">
                      <button
                        on:click={() => configOptions = { ...configOptions, authMethod: 'static' }}
                        class="p-4 rounded-lg border-2 transition-all {
                          configOptions.authMethod === 'static'
                            ? 'border-[var(--sg-success)] bg-[var(--sg-success-bg)]'
                            : 'border-[var(--sg-border)] hover:border-[var(--sg-border)]'
                        }"
                      >
                        <Icon icon="mdi:key-outline" width="24" height="24" class="text-[var(--sg-text-dim)] mb-1" />
                        <div class="text-sm font-medium">Static Secrets</div>
                        <div class="text-xs text-[var(--sg-text-dim)]">GitHub secrets</div>
                      </button>
                      <button
                        on:click={() => configOptions.provider !== 'azure' && (configOptions = { ...configOptions, authMethod: 'oidc' })}
                        disabled={configOptions.provider === 'azure'}
                        class="p-4 rounded-lg border-2 transition-all {
                          configOptions.provider === 'azure'
                            ? 'border-[var(--sg-border)] opacity-50 cursor-not-allowed'
                            : configOptions.authMethod === 'oidc'
                              ? 'border-[var(--sg-warning)] bg-[var(--sg-warning-bg)]'
                              : 'border-[var(--sg-border)] hover:border-[var(--sg-border)]'
                        }"
                      >
                        <Icon icon="mdi:shield-lock-outline" width="24" height="24" class="text-[var(--sg-text-dim)] mb-1" />
                        <div class="text-sm font-medium">OIDC</div>
                        <div class="text-xs text-[var(--sg-text-dim)]">
                          {configOptions.provider === 'azure' ? 'Coming soon' : 'Recommended'}
                        </div>
                      </button>
                    </div>
                    
                    <!-- Documentation link for selected auth method -->
                    {#if configOptions.authMethod === 'static' || configOptions.authMethod === 'oidc'}
                      <div class="mt-3 p-3 bg-[var(--sg-accent-bg)] rounded-lg border border-[var(--sg-accent)]">
                        <div class="flex items-center justify-between">
                          <div class="flex items-center text-sm text-[var(--sg-accent)]">
                            <Icon icon="mdi:information-outline" width="16" height="16" class="mr-2" />
                            <span>
                              {#if configOptions.authMethod === 'static'}
                                Setup requires adding secrets to your GitHub repository
                              {:else}
                                OIDC provides secure, temporary credentials
                              {/if}
                            </span>
                          </div>
                          <a 
                            href="https://docs.terrateam.io/cloud-providers/{configOptions.provider}/"
                            target="_blank"
                            rel="noopener noreferrer"
                            class="text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] flex items-center"
                            on:click|stopPropagation
                          >
                            View Setup Guide
                            <Icon icon="mdi:open-in-new" width="14" height="14" class="ml-1" />
                          </a>
                        </div>
                      </div>
                    {/if}
                  </div>
                {/if}

                <!-- Repository Structure -->
                <div class="mb-4">
                  <div class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
                    Repository Structure
                  </div>
                  <div class="space-y-2">
                    {#each [
                      { value: 'directories', icon: '📁', name: 'Directories', desc: 'Separate folders' },
                      { value: 'tfvars', icon: '📄', name: 'tfvars Files', desc: 'Variable files' },
                      { value: 'workspaces', icon: '🔀', name: 'Workspaces', desc: 'Terraform workspaces' }
                    ] as structure}
                      <button
                        on:click={() => setRepoStructure(structure.value)}
                        class="w-full p-3 rounded-lg border-2 text-left transition-all {
                          configOptions.repoStructure === structure.value
                            ? 'border-[var(--sg-accent)] bg-[var(--sg-accent-bg)]'
                            : 'border-[var(--sg-border)] hover:border-[var(--sg-border)]'
                        }"
                      >
                        <div class="flex items-center">
                          <div class="text-lg mr-3">{structure.icon}</div>
                          <div>
                            <div class="text-sm font-medium">{structure.name}</div>
                            <div class="text-xs text-[var(--sg-text-dim)]">{structure.desc}</div>
                          </div>
                        </div>
                      </button>
                    {/each}
                  </div>
                </div>

                <!-- Multiple {$currentVCSProvider === 'gitlab' ? 'GitLab' : 'GitHub'} Environments -->
                <div>
                  <button
                    on:click={() => configOptions = { ...configOptions, multipleEnvironments: !configOptions.multipleEnvironments }}
                    class="w-full p-3 rounded-lg border-2 transition-all {
                      configOptions.multipleEnvironments
                        ? 'border-[var(--sg-purple)] bg-[var(--sg-purple-bg)]'
                        : 'border-[var(--sg-border)] hover:border-[var(--sg-border)]'
                    }"
                  >
                    <div>
                      <div class="flex items-center justify-between">
                        <div class="flex items-center">
                          <div class="text-lg mr-3">🏗️</div>
                          <div class="flex items-center gap-3">
                            <span class="text-sm font-medium">Multiple {$currentVCSProvider === 'gitlab' ? 'GitLab' : 'GitHub'} Environments</span>
                            <a
                              href="https://docs.terrateam.io/advanced-workflows/multiple-environments/"
                              target="_blank"
                              rel="noopener noreferrer"
                              on:click|stopPropagation
                              class="text-[var(--sg-text-dim)] hover:text-[var(--sg-accent)] transition-colors"
                              title="Learn more about Multiple {$currentVCSProvider === 'gitlab' ? 'GitLab' : 'GitHub'} Environments (opens in new tab)"
                            >
                              <Icon icon="mdi:open-in-new" width="16" height="16" />
                            </a>
                          </div>
                        </div>
                        <div class="w-5 h-5 rounded border-2 flex-shrink-0 ml-3 {
                          configOptions.multipleEnvironments
                            ? 'bg-[var(--sg-purple)] border-[var(--sg-purple)]'
                            : 'border-[var(--sg-border)]'
                        } flex items-center justify-center">
                          {#if configOptions.multipleEnvironments}
                            <svg class="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                            </svg>
                          {/if}
                        </div>
                      </div>
                    </div>
                  </button>
                </div>

                <!-- Private Runners -->
                <div class="mt-4">
                  <div class="p-4 rounded-lg border-2 border-[var(--sg-border)] bg-[var(--sg-bg-1)]">
                    <div class="flex items-start">
                      <div class="text-lg mr-3 flex-shrink-0">🔒</div>
                      <div class="flex-1 min-w-0">
                        <div class="flex flex-wrap items-center gap-2 mb-2">
                          <span class="text-sm font-medium text-[var(--sg-text)]">Private Runners</span>
                          <span class="text-xs px-2 py-0.5 bg-[var(--sg-success-bg)] text-[var(--sg-success)] rounded-full font-medium whitespace-nowrap">Security Feature</span>
                        </div>
                        <p class="text-xs text-[var(--sg-text-dim)] mb-3">
                          Run Terrateam on your own infrastructure for enhanced security and compliance. 
                          Private runners keep your code and secrets within your network.
                        </p>
                        <div class="flex flex-col gap-2">
                          <div class="text-xs text-[var(--sg-text-dim)]">
                            <span class="block mb-1">Configured in:</span>
                            <code class="bg-[var(--sg-bg-2)] px-1.5 py-0.5 rounded text-xs break-all">.github/workflows/terrateam.yml</code>
                          </div>
                          <a 
                            href="https://docs.terrateam.io/security-and-compliance/private-runners/"
                            target="_blank"
                            rel="noopener noreferrer"
                            class="text-xs text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] flex items-center font-medium self-start"
                          >
                            Setup Guide
                            <Icon icon="mdi:open-in-new" width="14" height="14" class="ml-1" />
                          </a>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Right Column: Features -->
            <div class="space-y-6">
              <div class="bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)] p-6">
                <h3 class="text-lg font-semibold text-[var(--sg-text)] mb-4">Features</h3>
                
                {#each Object.entries(featureCategories) as [, category]}
                  <div class="mb-6 last:mb-0">
                    <h4 class="text-sm font-medium text-[var(--sg-text-muted)] mb-3 flex items-center">
                      <Icon icon={category.iconName} width="20" height="20" class="mr-2 text-[var(--sg-text-dim)]" />
                      {category.name}
                    </h4>
                    <div class="space-y-2">
                      {#each category.features as feature}
                        <button
                          on:click={() => toggleFeature(feature)}
                          class="w-full p-3 rounded-lg border transition-all text-left {configOptions[feature] 
                            ? 'border-[var(--sg-purple)] bg-[var(--sg-purple-bg)]'
                            : 'border-[var(--sg-border)] hover:border-[var(--sg-border)]'
                          }"
                        >
                          <div class="flex items-center justify-between">
                            <div class="flex-1">
                              <div class="flex items-center gap-2">
                                <span class="text-sm font-medium">{featureInfo[feature].name}</span>
                                <a 
                                  href={featureInfo[feature].docUrl}
                                  target="_blank"
                                  rel="noopener noreferrer"
                                  on:click|stopPropagation
                                  class="text-[var(--sg-text-dim)] hover:text-[var(--sg-accent)] transition-colors"
                                  title="Learn more about {featureInfo[feature].name} (opens in new tab)"
                                >
                                  <Icon icon="mdi:open-in-new" width="16" height="16" />
                                </a>
                              </div>
                              <div class="text-xs text-[var(--sg-text-dim)]">
                                {featureInfo[feature].description}
                              </div>
                            </div>
                            <div class="flex items-center ml-3">
                              <div class="w-5 h-5 rounded border-2 flex items-center justify-center"
                                class:bg-[var(--sg-purple)]={configOptions[feature]}
                                class:border-[var(--sg-purple)]={configOptions[feature]}
                                class:border-[var(--sg-border)]={!configOptions[feature]}
                              >
                                {#if configOptions[feature]}
                                  <svg class="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                                  </svg>
                                {/if}
                              </div>
                            </div>
                          </div>
                        </button>
                      {/each}
                    </div>
                  </div>
                {/each}
              </div>
            </div>
          </div>
        {/if}
      </div>

      <!-- Configuration Preview -->
      {#if selectedPreset === 'starter' && configOptions.provider === 'none'}
        <!-- Special message for starter with no provider -->
        <div class="bg-[var(--sg-success-bg)] rounded-lg border border-[var(--sg-success)] p-6">
          <div class="flex items-start">
            <div class="flex-shrink-0">
              <Icon icon="mdi:check-circle" width="24" height="24" class="text-[var(--sg-success)]" />
            </div>
            <div class="ml-3">
              <h3 class="text-lg font-semibold text-[var(--sg-success)] mb-2">
                No Configuration Needed!
              </h3>
              <p class="text-[var(--sg-success)] mb-4">
                Terrateam works out of the box without any cloud provider credentials. This is perfect for:
              </p>
              <ul class="list-disc list-inside text-[var(--sg-success)] space-y-1 mb-4">
                <li>Testing Terrateam with demo Terraform code</li>
                <li>Learning Terraform without cloud costs</li>
                <li>Running local Terraform providers</li>
                <li>Using Terraform for non-cloud resources</li>
              </ul>
              <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 border border-[var(--sg-success)]">
                <h4 class="font-semibold text-[var(--sg-success)] mb-2">Quick Start:</h4>
                <ol class="text-sm text-[var(--sg-success)] space-y-1">
                  <li>1. Push any Terraform files to your repository</li>
                  <li>2. Open a pull request</li>
                  <li>3. Terrateam will automatically run <code class="bg-[var(--sg-success-bg)] px-1 rounded">terraform plan</code></li>
                </ol>
              </div>
              <p class="text-sm text-[var(--sg-success)] mt-4">
                💡 When you're ready to use cloud resources, come back here and select your cloud provider above.
              </p>
            </div>
          </div>
        </div>
      {:else if selectedPreset === 'starter' && configOptions.provider !== 'none'}
        <!-- Special message for starter with cloud provider (static secrets only) -->
        <div class="bg-[var(--sg-accent-bg)] rounded-lg border border-[var(--sg-accent)] p-4 sm:p-6">
          <div class="flex flex-col sm:flex-row sm:items-start gap-3">
            <div class="flex-shrink-0 flex justify-center sm:block">
              <Icon icon="mdi:cloud-check" width="24" height="24" class="text-[var(--sg-accent)]" />
            </div>
            <div class="flex-1">
              <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-accent)] mb-2 text-center sm:text-left">
                No Configuration File Needed
              </h3>
              <p class="text-sm sm:text-base text-[var(--sg-accent)] mb-4 text-center sm:text-left">
                Terrateam works automatically with {configOptions.provider.toUpperCase()} using GitHub secrets. You don't need a configuration file!
              </p>
              
              <div class="bg-[var(--sg-bg-1)] rounded-lg p-3 sm:p-4 border border-[var(--sg-accent)] mb-4">
                <h4 class="font-semibold text-[var(--sg-accent)] mb-3 text-sm sm:text-base">Quick Setup:</h4>
                <ol class="text-xs sm:text-sm text-[var(--sg-accent)] space-y-3">
                  <li class="flex items-start">
                    <span class="font-semibold mr-2 flex-shrink-0">1.</span>
                    <div class="flex-1 min-w-0">
                      <span class="block mb-2">Add these secrets to your GitHub repository:</span>
                      <div class="font-mono text-xs bg-[var(--sg-accent-bg)] p-2 rounded overflow-x-auto">
                        {getSecretsForProvider(configOptions.provider)}
                      </div>
                    </div>
                  </li>
                  <li class="flex items-start">
                    <span class="font-semibold mr-2 flex-shrink-0">2.</span>
                    <span class="flex-1">Push Terraform files to any directory in your repository</span>
                  </li>
                  <li class="flex items-start">
                    <span class="font-semibold mr-2 flex-shrink-0">3.</span>
                    <div class="flex-1">
                      <span>Open a pull request - Terrateam will automatically run </span>
                      <code class="inline bg-[var(--sg-accent-bg)] px-1.5 py-0.5 rounded text-xs">terraform plan</code>
                    </div>
                  </li>
                </ol>
              </div>
              
              <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                <p class="text-xs sm:text-sm text-[var(--sg-accent)] text-center sm:text-left">
                  💡 Want to add features later? Use the Custom configuration option.
                </p>
                <a 
                  href="https://docs.terrateam.io/cloud-providers/{configOptions.provider}/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent-hover)] font-medium flex items-center"
                >
                  {configOptions.provider.toUpperCase()} Setup Guide
                  <Icon icon="mdi:open-in-new" width="14" height="14" class="ml-1" />
                </a>
              </div>
            </div>
          </div>
        </div>
      {:else if selectedPreset !== 'starter'}
        <div class="bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)]">
        <div class="border-b border-[var(--sg-border)] p-3 md:p-4">
          <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div>
              <h3 class="font-semibold text-sm md:text-base text-[var(--sg-text)]">
                {generatedConfig.includes('No configuration file is required') ? 'Getting Started' : 'Configuration Preview'}
              </h3>
              <p class="text-xs md:text-sm text-[var(--sg-text-dim)]">
                {generatedConfig.includes('No configuration file is required') 
                  ? 'No config file needed - Terrateam works out of the box!' 
                  : 'Live preview of your .terrateam/config.yml'}
              </p>
            </div>
            <button
              on:click={() => copyToClipboard()}
              class="inline-flex items-center justify-center px-2.5 md:px-3 py-1.5 md:py-2 border rounded-md text-xs md:text-sm font-medium transition-all duration-200 {copySuccess 
                ? 'border-[var(--sg-success)] text-[var(--sg-success)] bg-[var(--sg-success-bg)]' 
                : 'border-[var(--sg-border)] text-[var(--sg-text-muted)] bg-[var(--sg-bg-1)] hover:bg-[var(--sg-bg-2)]'}"
            >
              {#if copySuccess}
                <svg class="w-3 md:w-4 h-3 md:h-4 mr-1.5 md:mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                </svg>
                Copied!
              {:else}
                <svg class="w-3 md:w-4 h-3 md:h-4 mr-1.5 md:mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                </svg>
                Copy
              {/if}
            </button>
          </div>
        </div>
        <div class="p-3 md:p-4">
          {#if generatedConfig.includes('No configuration file is required')}
            <pre class="bg-[var(--sg-bg-1)] rounded-lg p-3 md:p-4 text-xs font-mono overflow-x-auto whitespace-pre-wrap transition-all duration-300 {copySuccess ? 'ring-2 ring-[var(--sg-success)] ring-opacity-50' : ''}"><code>{generatedConfig}</code></pre>
          {:else}
            <pre class="config-hljs bg-[var(--sg-bg-1)] rounded-lg p-3 md:p-4 text-xs font-mono overflow-x-auto whitespace-pre-wrap transition-all duration-300 {copySuccess ? 'ring-2 ring-[var(--sg-success)] ring-opacity-50' : ''}"><code class="language-yaml">{@html highlightedConfig}</code></pre>
          {/if}
        </div>
      </div>

      <!-- Next Steps -->
      <div class="mt-6 bg-[var(--sg-accent-bg)] rounded-lg border border-[var(--sg-accent)] p-4">
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <svg class="w-5 h-5 text-[var(--sg-accent)]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <div class="ml-3 flex-1">
            <h4 class="text-sm font-semibold text-[var(--sg-accent)] mb-2">Next Steps</h4>
            {#if generatedConfig.includes('No configuration file is required')}
              <ol class="text-sm text-[var(--sg-accent)] space-y-1">
                <li>1. No configuration file needed!</li>
                {#if configOptions.provider !== 'none'}
                  <li>2. Add {getSecretsForProvider(configOptions.provider)} to your GitHub repository secrets</li>
                  <li>3. Push Terraform files to any directory</li>
                  <li>4. Open a pull request - Terrateam will automatically plan your changes</li>
                {:else}
                  <li>2. Push Terraform files to any directory</li>
                  <li>3. Open a pull request - Terrateam will automatically plan your changes</li>
                {/if}
              </ol>
            {:else}
              <ol class="text-sm text-[var(--sg-accent)] space-y-1">
                <li>1. Copy the generated configuration</li>
                <li>2. Tailor the configuration to match your repository structure and requirements</li>
                <li>3. Create <code class="bg-[var(--sg-accent-bg)] px-1 rounded">.terrateam/config.yml</code> in your repository</li>
                {#if configOptions.provider !== 'none'}
                  <li>4. {configOptions.authMethod === 'static' 
                    ? `Add ${getSecretsForProvider(configOptions.provider)} to GitHub secrets` 
                    : `Configure ${configOptions.provider.toUpperCase()} OIDC`}</li>
                  <li>5. Create a pull request to test your configuration</li>
                {:else}
                  <li>4. Create a pull request to test your configuration</li>
                {/if}
              </ol>
            {/if}
            <div class="mt-3 flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-0">
              <button 
                on:click={() => openDocumentation('https://docs.terrateam.io/')}
                class="text-xs md:text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent)] underline"
              >
                View documentation
              </button>
              <span class="hidden sm:inline mx-1 md:mx-2 text-[var(--sg-accent)]">·</span>
              <button
                on:click={() => window.open(EXTERNAL_URLS.SLACK, '_blank')}
                class="text-xs md:text-sm text-[var(--sg-accent)] hover:text-[var(--sg-accent)] underline"
              >
                Get help on Slack
              </button>
            </div>
          </div>
        </div>
      </div>
      {/if}
    {/if}
  </div>
  
  <!-- Toast Notification -->
  {#if showToast}
    <div class="fixed bottom-4 right-4 left-4 sm:left-auto z-50 config-animate-slide-up">
      <div class="bg-[var(--sg-success)] text-white px-4 md:px-6 py-2.5 md:py-3 rounded-lg shadow-lg flex items-center space-x-3">
        <svg class="w-4 md:w-5 h-4 md:h-5 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <div>
          <p class="font-medium text-sm md:text-base">Configuration copied!</p>
          <p class="text-xs md:text-sm text-white">Ready to paste into .terrateam/config.yml</p>
        </div>
      </div>
    </div>
  {/if}
</PageLayout>

