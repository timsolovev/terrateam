<script lang="ts">
  import PageLayout from './components/layout/PageLayout.svelte';
  import { api, isApiError } from './api';
  import { onMount } from 'svelte';
  import type { Installation, Repository, GitLabGroup, ServerConfig } from './types';
  import { repositoryService } from './services/repository-service';
  import { Icon, LoadingSpinner } from './components';
  import GitLabTokenInstructions from './components/gitlab/GitLabTokenInstructions.svelte';
  import { currentVCSProvider } from './stores';
  import { get } from 'svelte/store';
  import { VCS_PROVIDERS } from './vcs/providers';
  import { analytics } from './analytics';
  import { onDestroy } from 'svelte';

  // Track time spent
  let startTime = Date.now();

  // Wizard state
  type WizardStep = 'assessment' | 'path-selection' | 'github-demo-setup' | 'gitlab-demo-setup' | 'github-repo-setup' | 'gitlab-setup' | 'validation' | 'success';
  type DemoStep = 'install-app' | 'fork' | 'enable-actions' | 'make-changes' | 'success';
  type GitLabDemoStep = 'select-group' | 'fork' | 'submit-token' | 'configure-webhook' | 'configure-variables' | 'make-changes' | 'success';
  type RepoStep = 'install-app' | 'select-repo' | 'add-workflow' | 'configure' | 'test' | 'success';
  type GitLabStep = 'select-group' | 'select-repo' | 'submit-token' | 'configure-webhook' | 'configure-variables' | 'add-pipeline' | 'success';
  let currentStep: WizardStep = 'assessment';
  let selectedPath: 'demo' | 'repo' | null = null;
  let currentDemoStep: DemoStep = 'install-app';
  let currentGitLabDemoStep: GitLabDemoStep = 'select-group';
  let currentRepoStep: RepoStep = 'install-app';
  let currentGitLabStep: GitLabStep = 'select-group';

  // Server configuration
  let serverConfig: ServerConfig | null = null;
  let githubAppUrl: string = 'https://github.com/apps/terrateam-action'; // fallback URL

  // API data
  let installations: Installation[] = [];
  let selectedInstallation: Installation | null = null;
  let selectedInstallationId: string = '';
  let repositories: Repository[] = [];
  let isLoadingAssessment = true;
  let assessmentError: string | null = null;

  // Assessment results
  let hasInstallations = false;
  let hasConfiguredRepos = false;
  let recommendedPath: 'demo' | 'repo' = 'demo';

  // Get current VCS provider terminology
  $: currentProvider = $currentVCSProvider || 'github';
  $: terminology = VCS_PROVIDERS[currentProvider]?.terminology || VCS_PROVIDERS.github.terminology;

  // Demo wizard state
  let demoStepCompleted = {
    'install-app': false,
    fork: false,
    'enable-actions': false,
    'make-changes': false
  };
  let checkingAppInstallation = false;

  // GitLab Demo wizard state
  let gitlabDemoStepCompleted = {
    'select-group': false,
    fork: false,
    'submit-token': false,
    'configure-webhook': false,
    'configure-variables': false,
    'make-changes': false
  };
  let gitlabDemoGroups: GitLabGroup[] = [];
  let selectedGitLabDemoGroup: GitLabGroup | null = null;
  let isLoadingGitLabGroups = false;
  let gitlabGroupsError: string | null = null;
  let forkedProjectPath: string = '';  // Store the forked project path
  let webhookUrl: string = '';
  let webhookSecret: string = '';
  let checkingWebhook = false;
  let webhookVerificationError: string | null = null;

  // Repository wizard state
  let repoStepCompleted = {
    'install-app': false,
    'select-repo': false,
    'add-workflow': false,
    'configure': false,
    'test': false
  };
  let selectedRepository: Repository | null = null;
  let isLoadingRepos = false;
  let repoLoadError: string | null = null;

  // GitLab wizard state
  let gitlabStepCompleted = {
    'select-group': false,
    'select-repo': false,
    'submit-token': false,
    'configure-webhook': false,
    'configure-variables': false,
    'add-pipeline': false
  };

  // Token submission state
  let gitlabAccessToken = '';
  let isSubmittingGitLabToken = false;
  let gitlabTokenSubmitted = false;
  let gitlabTokenError: string | null = null;
  let gitlabGroups: GitLabGroup[] = [];
  let selectedGitLabGroup: GitLabGroup | null = null;
  let isLoadingGitLabSetupGroups = false;
  let gitlabSetupGroupsError: string | null = null;
  let gitlabRepos: Repository[] = [];
  let manualGitLabProject = '';
  let isAddingGitLabProject = false;
  let copiedYaml = false;

  onMount(async () => {
    // Track getting started page view
    analytics.track('getting_started_viewed', {
      vcs_provider: get(currentVCSProvider)
    });

    // Fetch server config first to get GitHub app URL
    try {
      serverConfig = await api.getServerConfig();
      if (serverConfig?.github?.app_url) {
        githubAppUrl = serverConfig.github.app_url;
      }
    } catch (error) {
      console.error('Failed to fetch server config:', error);
      // Will use fallback URL
    }

    await runSmartAssessment();
  });

  onDestroy(() => {
    // Track abandonment if user leaves before completing
    if (currentStep !== 'success') {
      const timeSpent = Math.round((Date.now() - startTime) / 1000);
      analytics.track('getting_started_abandoned', {
        last_step: currentStep,
        last_demo_step: currentDemoStep,
        last_gitlab_demo_step: currentGitLabDemoStep,
        last_repo_step: currentRepoStep,
        last_gitlab_step: currentGitLabStep,
        path: selectedPath,
        vcs_provider: currentProvider,
        time_spent_seconds: timeSpent,
        has_installations: hasInstallations,
        has_configured_repos: hasConfiguredRepos,
        selected_repository: selectedRepository?.name,
        selected_gitlab_group: selectedGitLabGroup?.name || selectedGitLabDemoGroup?.name
      });
    }
  });

  async function runSmartAssessment(): Promise<void> {
    try {
      isLoadingAssessment = true;
      assessmentError = null;

      // Check user's current installations
      const provider = get(currentVCSProvider);

      // For GitLab, check if we should show the setup wizard
      if (provider === 'gitlab') {
        try {
          const installationsResponse = await api.getUserInstallations(provider);
          installations = installationsResponse.installations;
          hasInstallations = installations.length > 0;
        } catch (error) {
          // If GitLab installations endpoint returns 404, user needs to go through setup
          if (isApiError(error) && error.status === 404) {
            // No installations yet - proceed with normal flow
            hasInstallations = false;
            installations = [];
          } else {
            throw error;
          }
        }
      } else {
        // GitHub flow remains the same
        const installationsResponse = await api.getUserInstallations(provider);
        installations = installationsResponse.installations;
        hasInstallations = installations.length > 0;
      }

      // Initialize selected installation if we have installations
      if (hasInstallations && !selectedInstallation) {
        selectedInstallation = installations[0];
        selectedInstallationId = installations[0].id;
      }

      if (hasInstallations) {
        // Check if any repos are already configured
        for (const installation of installations) {
          try {
            const dirspacesResponse = await api.getInstallationDirspaces(installation.id);
            if (dirspacesResponse.dirspaces && dirspacesResponse.dirspaces.length > 0) {
              hasConfiguredRepos = true;
              break;
            }
          } catch (error) {
            // Continue checking other installations
          }
        }
      }

      // Smart recommendation based on assessment
      if (hasConfiguredRepos) {
        recommendedPath = 'repo'; // User already has working setup
      } else if (hasInstallations) {
        recommendedPath = 'repo'; // User has installations, help them configure
      } else {
        recommendedPath = 'demo'; // New user, start with demo
      }

      currentStep = 'path-selection';
    } catch (error) {
      console.error('Assessment failed:', error);
      assessmentError = 'Unable to assess your current setup. You can still proceed with manual setup.';
      currentStep = 'path-selection';
    } finally {
      isLoadingAssessment = false;
    }
  }

  function selectPath(path: 'demo' | 'repo'): void {
    selectedPath = path;

    // Track path selection
    analytics.track('getting_started_path_selected', {
      path: path,
      vcs_provider: currentProvider,
      has_installations: hasInstallations,
      has_configured_repos: hasConfiguredRepos
    });

    if (path === 'demo') {
      // Branch demo based on VCS provider - explicit GitHub vs GitLab
      if (currentProvider === 'gitlab') {
        currentStep = 'gitlab-demo-setup';
        // Load GitLab groups for demo
        loadGitLabGroups();
      } else {
        currentStep = 'github-demo-setup';
      }
    } else {
      // Branch repo setup based on VCS provider - explicit GitHub vs GitLab
      if (currentProvider === 'gitlab') {
        currentStep = 'gitlab-setup';
        loadGitLabSetupGroups();
      } else {
        currentStep = 'github-repo-setup';
        // Always start at the install-app step to give users the option to install on different orgs
      }
    }
  }

  function goBack(): void {
    switch (currentStep) {
      case 'github-demo-setup':
      case 'gitlab-demo-setup':
      case 'github-repo-setup':
      case 'gitlab-setup':
        currentStep = 'path-selection';
        selectedPath = null;
        break;
      case 'validation':
        if (selectedPath === 'demo') {
          if (currentProvider === 'gitlab') {
            currentStep = 'gitlab-demo-setup';
          } else {
            currentStep = 'github-demo-setup';
          }
        } else if (currentProvider === 'gitlab') {
          currentStep = 'gitlab-setup';
        } else {
          currentStep = 'github-repo-setup';
        }
        break;
      default:
        currentStep = 'path-selection';
    }
  }

  function openExternalLink(url: string, linkType?: string): void {
    // Track external link clicks
    analytics.track('getting_started_external_link_clicked', {
      url: url,
      link_type: linkType || 'unknown',
      current_step: currentStep,
      current_demo_step: currentDemoStep,
      current_repo_step: currentRepoStep,
      path: selectedPath,
      vcs_provider: currentProvider
    });

    window.open(url, '_blank');
  }


  function openConfigurationWizard(): void {
    if (selectedInstallation) {
      window.location.hash = `#/i/${selectedInstallation.id}/configuration`;
    } else {
      window.location.hash = '#/configuration';
    }
  }

  // Demo wizard functions
  function markDemoStepComplete(step: DemoStep): void {
    if (step !== 'success') {
      demoStepCompleted[step] = true;
    }

    // Track step completion
    analytics.track('getting_started_step_completed', {
      path: 'demo',
      vcs_provider: 'github',
      step: step,
      step_index: ['install-app', 'fork', 'enable-actions', 'make-changes'].indexOf(step) + 1
    });

    // Auto-advance to next step
    const steps: DemoStep[] = ['install-app', 'fork', 'enable-actions', 'make-changes', 'success'];
    const currentIndex = steps.indexOf(currentDemoStep);
    if (currentIndex < steps.length - 1) {
      currentDemoStep = steps[currentIndex + 1];
    }

    // Track completion of entire flow
    if (currentDemoStep === 'success') {
      const timeSpent = Math.round((Date.now() - startTime) / 1000);
      analytics.track('getting_started_completed', {
        path: 'demo',
        vcs_provider: 'github',
        time_spent_seconds: timeSpent
      });
    }
  }

  function goToDemoStep(step: DemoStep): void {
    currentDemoStep = step;
  }

  function goToGitLabDemoStep(step: GitLabDemoStep): void {
    currentGitLabDemoStep = step;
  }

  // GitLab demo wizard functions
  async function loadGitLabGroups(): Promise<void> {
    try {
      isLoadingGitLabGroups = true;
      gitlabGroupsError = null;
      gitlabDemoGroups = await api.getGitLabGroups();
    } catch (error) {
      console.error('Failed to load GitLab groups:', error);
      gitlabGroupsError = 'Failed to load groups. Please try again.';
    } finally {
      isLoadingGitLabGroups = false;
    }
  }

  function selectGitLabDemoGroup(group: GitLabGroup): void {
    selectedGitLabDemoGroup = group;
    // Pre-fill the expected project path
    forkedProjectPath = `${group.name}/kick-the-tires`;

    // Track group selection
    analytics.track('getting_started_gitlab_group_selected', {
      path: 'demo',
      vcs_provider: 'gitlab',
      group: group.name
    });

    markGitLabDemoStepComplete('select-group');
  }

  function markGitLabDemoStepComplete(step: GitLabDemoStep): void {
    if (step !== 'success') {
      gitlabDemoStepCompleted[step] = true;
    }

    // Track step completion
    analytics.track('getting_started_step_completed', {
      path: 'demo',
      vcs_provider: 'gitlab',
      step: step,
      step_index: ['select-group', 'fork', 'submit-token', 'configure-webhook', 'configure-variables', 'make-changes'].indexOf(step) + 1,
      group: selectedGitLabDemoGroup?.name
    });

    // Auto-advance to next step
    const steps: GitLabDemoStep[] = ['select-group', 'fork', 'submit-token', 'configure-webhook', 'configure-variables', 'make-changes', 'success'];
    const currentIndex = steps.indexOf(currentGitLabDemoStep);
    if (currentIndex < steps.length - 1) {
      currentGitLabDemoStep = steps[currentIndex + 1];
    }

    // Track completion of entire flow
    if (currentGitLabDemoStep === 'success') {
      const timeSpent = Math.round((Date.now() - startTime) / 1000);
      analytics.track('getting_started_completed', {
        path: 'demo',
        vcs_provider: 'gitlab',
        time_spent_seconds: timeSpent,
        group: selectedGitLabDemoGroup?.name
      });
    }

    // Load webhook config when entering webhook step
    if (currentGitLabDemoStep === 'configure-webhook' && selectedGitLabDemoGroup) {
      loadWebhookConfig();
    }
  }

  async function loadWebhookConfig(): Promise<void> {
    if (!selectedGitLabDemoGroup) return;

    try {
      const config = await api.getGitLabWebhookConfig(selectedGitLabDemoGroup.id.toString());
      webhookUrl = config.webhook_url;
      webhookSecret = config.webhook_secret || '';
    } catch (error) {
      console.error('Failed to load webhook config:', error);
      // Set defaults if API fails
      webhookUrl = 'https://app.terrateam.io/webhook/gitlab';
      webhookSecret = 'Contact support for webhook secret';
    }
  }

  async function checkWebhook(): Promise<void> {
    if (!selectedGitLabDemoGroup) return;

    try {
      checkingWebhook = true;
      webhookVerificationError = null;

      // Track webhook verification attempt
      analytics.track('getting_started_gitlab_webhook_check', {
        path: 'demo',
        vcs_provider: 'gitlab',
        group: selectedGitLabDemoGroup.name
      });

      const config = await api.getGitLabWebhookConfig(selectedGitLabDemoGroup.id.toString());
      const isActive = config.state === 'installed';

      if (isActive) {
        webhookVerificationError = null;

        // Track successful webhook configuration
        analytics.track('getting_started_gitlab_webhook_configured', {
          path: 'demo',
          vcs_provider: 'gitlab',
          group: selectedGitLabDemoGroup.name
        });

        markGitLabDemoStepComplete('configure-webhook');
      } else {
        webhookVerificationError = 'Webhook is not active yet. Please test it with a Push Event in GitLab.';
      }
    } catch (error) {
      console.error('Failed to check webhook:', error);
      webhookVerificationError = 'Unable to verify webhook. Please ensure you\'ve added it and tested with a Push Event.';
    } finally {
      checkingWebhook = false;
    }
  }

  async function checkAppInstallation(): Promise<void> {
    try {
      checkingAppInstallation = true;

      // Track app installation check
      analytics.track('getting_started_check_installation', {
        path: 'demo',
        vcs_provider: currentProvider,
        had_installations_before: hasInstallations
      });

      // Re-fetch installations to see if app was installed
      const installationsResponse = await api.getUserInstallations();
      const newInstallations = installationsResponse.installations;

      // If we already had installations, just proceed
      if (hasInstallations && installations.length > 0) {
        markDemoStepComplete('install-app');
      }
      // Check if we have more installations than before
      else if (newInstallations.length > installations.length) {
        installations = newInstallations;
        hasInstallations = true;

        // Track successful installation
        analytics.track('getting_started_app_installed', {
          path: 'demo',
          vcs_provider: currentProvider,
          installation_count: newInstallations.length
        });
        markDemoStepComplete('install-app');
      } else {
        // Show message that we didn't detect the installation
        alert('We didn\'t detect the GitHub App installation. Make sure you installed it and try again, or continue manually.');
      }
    } catch (error) {
      console.error('Failed to check app installation:', error);
      alert('Unable to check installation status. You can continue manually.');
    } finally {
      checkingAppInstallation = false;
    }
  }

  // Repository wizard functions
  function markRepoStepComplete(step: RepoStep): void {
    if (step !== 'success') {
      repoStepCompleted[step] = true;
    }

    // Track step completion
    analytics.track('getting_started_step_completed', {
      path: 'repo',
      vcs_provider: currentProvider,
      step: step,
      step_index: ['install-app', 'select-repo', 'add-workflow', 'configure', 'test'].indexOf(step) + 1,
      repository: selectedRepository?.name
    });

    // Auto-advance to next step
    const steps: RepoStep[] = ['install-app', 'select-repo', 'add-workflow', 'configure', 'test', 'success'];
    const currentIndex = steps.indexOf(currentRepoStep);
    if (currentIndex < steps.length - 1) {
      currentRepoStep = steps[currentIndex + 1];
    }

    // Track completion of entire flow
    if (currentRepoStep === 'success') {
      const timeSpent = Math.round((Date.now() - startTime) / 1000);
      analytics.track('getting_started_completed', {
        path: 'repo',
        vcs_provider: currentProvider,
        time_spent_seconds: timeSpent,
        repository: selectedRepository?.name,
        installation: selectedInstallation?.name
      });
    }
  }

  function goToRepoStep(step: RepoStep): void {
    currentRepoStep = step;
  }

  async function loadRepositories(forceRefresh: boolean = false): Promise<void> {
    if (!selectedInstallation) return;

    try {
      isLoadingRepos = true;
      repoLoadError = null;

      // Load repositories from centralized service
      const result = await repositoryService.loadRepositories(selectedInstallation, forceRefresh);
      repositories = result.repositories;

      if (result.error) {
        repoLoadError = result.error;
      }

    } catch (error) {
      console.error('Failed to load repositories:', error);
      repoLoadError = 'Unable to load repositories. Please try again.';
    } finally {
      isLoadingRepos = false;
    }
  }

  async function refreshRepositories(): Promise<void> {
    if (!selectedInstallation || isLoadingRepos) return;

    try {
      isLoadingRepos = true;
      repoLoadError = null;

      // Call the refresh endpoint - this triggers a background job to sync with GitHub
      const refreshResponse = await api.refreshInstallationRepos(selectedInstallation.id);

      // Poll the task status
      let attempts = 0;
      const maxAttempts = 30; // 30 seconds max

      while (attempts < maxAttempts) {
        await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second

        try {
          const taskStatus = await api.getTask(refreshResponse.id);

          if (taskStatus.state === 'completed') {
            // Refresh completed successfully, reload repositories with force refresh
            await loadRepositories(true);
            break;
          } else if (taskStatus.state === 'failed' || taskStatus.state === 'aborted') {
            throw new Error(`Repository refresh ${taskStatus.state}`);
          }
        } catch (taskError) {
          console.warn('Failed to check task status:', taskError);
          // Continue polling even if status check fails
        }

        attempts++;
      }

      if (attempts >= maxAttempts) {
        // Timeout - still reload repositories as they might have been updated
        await loadRepositories(true);
      }
    } catch (err) {
      console.error('Error refreshing repositories:', err);
      repoLoadError = 'Failed to refresh repositories. Please try again.';
    } finally {
      isLoadingRepos = false;
    }
  }

  function selectRepository(repo: Repository): void {
    selectedRepository = repo;

    // Track repository selection
    analytics.track('getting_started_repository_selected', {
      path: 'repo',
      vcs_provider: currentProvider,
      repository: repo.name,
      repository_setup_status: repo.setup ? 'complete' : 'pending',
      installation: selectedInstallation?.name
    });

    markRepoStepComplete('select-repo');
  }

  // Automatically refresh repositories when installation is selected and we're on select-repo step
  // This ensures we get the latest repository list from GitHub, including recently installed repos
  $: if (selectedInstallation && currentRepoStep === 'select-repo') {
    refreshRepositories();
  }

  async function checkRepoAppInstallation(): Promise<void> {
    try {
      checkingAppInstallation = true;

      // Re-fetch installations to see if app was installed
      const installationsResponse = await api.getUserInstallations();
      const newInstallations = installationsResponse.installations;

      // If we already had installations, just proceed
      if (hasInstallations && installations.length > 0) {
        markRepoStepComplete('install-app');
      }
      // Check if we have more installations than before
      else if (newInstallations.length > installations.length) {
        installations = newInstallations;
        hasInstallations = true;
        markRepoStepComplete('install-app');

        // Set the first installation as selected if none selected
        if (!selectedInstallation && newInstallations.length > 0) {
          selectedInstallation = newInstallations[0];
          selectedInstallationId = newInstallations[0].id;
        }
      } else {
        // Show message that we didn't detect the installation
        alert('We didn\'t detect the GitHub App installation. Make sure you installed it and try again, or continue manually.');
      }
    } catch (error) {
      console.error('Failed to check app installation:', error);
      alert('Unable to check installation status. You can continue manually.');
    } finally {
      checkingAppInstallation = false;
    }
  }

  // GitLab wizard functions
  function markGitLabStepComplete(step: GitLabStep): void {
    if (step !== 'success') {
      gitlabStepCompleted[step] = true;
    }

    // Track step completion
    analytics.track('getting_started_step_completed', {
      path: 'repo',
      vcs_provider: 'gitlab',
      step: step,
      step_index: ['select-group', 'select-repo', 'submit-token', 'configure-webhook', 'configure-variables', 'add-pipeline'].indexOf(step) + 1,
      group: selectedGitLabGroup?.name,
      repository: manualGitLabProject
    });

    // Auto-advance to next step
    const steps: GitLabStep[] = ['select-group', 'select-repo', 'submit-token', 'configure-webhook', 'configure-variables', 'add-pipeline', 'success'];
    const currentIndex = steps.indexOf(currentGitLabStep);
    if (currentIndex < steps.length - 1) {
      currentGitLabStep = steps[currentIndex + 1];
    }

    // Track completion of entire flow
    if (currentGitLabStep === 'success') {
      const timeSpent = Math.round((Date.now() - startTime) / 1000);
      analytics.track('getting_started_completed', {
        path: 'repo',
        vcs_provider: 'gitlab',
        time_spent_seconds: timeSpent,
        group: selectedGitLabGroup?.name,
        repository: manualGitLabProject
      });
    }

    // Load webhook config when entering configure-webhook step
    if (currentGitLabStep === 'configure-webhook' && selectedGitLabGroup) {
      loadGitLabWebhookConfig();
    }
  }

  function goToGitLabStep(step: GitLabStep): void {
    currentGitLabStep = step;
  }

  // GitLab group and repository management
  async function loadGitLabSetupGroups(): Promise<void> {
    try {
      isLoadingGitLabSetupGroups = true;
      gitlabSetupGroupsError = null;
      gitlabGroups = await api.getGitLabGroups();
    } catch (error) {
      console.error('Failed to load GitLab groups:', error);
      gitlabSetupGroupsError = 'Failed to load groups. Please try again.';
    } finally {
      isLoadingGitLabSetupGroups = false;
    }
  }

  function selectGitLabGroup(group: GitLabGroup): void {
    selectedGitLabGroup = group;

    // Track group selection
    analytics.track('getting_started_gitlab_group_selected', {
      path: 'repo',
      vcs_provider: 'gitlab',
      group: group.name
    });

    // Clear previously selected repo when group changes
    markGitLabStepComplete('select-group');
  }


  async function addGitLabProject(): Promise<void> {
    if (!manualGitLabProject.trim() || !selectedGitLabGroup) return;

    try {
      isAddingGitLabProject = true;

      // Construct the full repository path
      const repoName = manualGitLabProject.trim();
      const fullPath = `${selectedGitLabGroup.name}/${repoName}`;

      // Track repository addition
      analytics.track('getting_started_gitlab_repo_added', {
        path: 'repo',
        vcs_provider: 'gitlab',
        group: selectedGitLabGroup.name,
        repository: repoName,
        full_path: fullPath
      });

      // Create a temporary repository object
      // In a real implementation, this would call an API to register the project
      const newRepo: Repository = {
        id: `manual-${Date.now()}`, // Temporary ID
        name: fullPath, // Store the full path as the name
        installation_id: selectedGitLabGroup.id.toString(),
        setup: false, // Will be set to true once webhook events are received
        updated_at: new Date().toISOString()
      };

      // Add to the list if not already present
      const exists = gitlabRepos.some(r => r.name === newRepo.name);
      if (!exists) {
        gitlabRepos = [...gitlabRepos, newRepo];
        // Don't clear manualGitLabProject - we need it for the webhook URL
        // Auto-advance to the next step
        markGitLabStepComplete('select-repo');
      } else {
        // Repository already exists in the list
      }
    } catch (error) {
      console.error('Failed to add GitLab project:', error);
    } finally {
      isAddingGitLabProject = false;
    }
  }

  async function loadGitLabWebhookConfig(): Promise<void> {
    if (!selectedGitLabGroup) return;

    try {
      const config = await api.getGitLabWebhookConfig(selectedGitLabGroup.id.toString());
      webhookUrl = config.webhook_url;
      webhookSecret = config.webhook_secret || '';
    } catch (error) {
      console.error('Failed to load GitLab webhook config:', error);
      // Set defaults if API fails
      webhookUrl = 'https://app.terrateam.io/webhook/gitlab';
      webhookSecret = 'Contact support for webhook secret';
    }
  }

  // Load GitLab groups when entering the GitLab setup flow
  $: if (currentStep === 'gitlab-setup' && currentGitLabStep === 'select-group') {
    loadGitLabSetupGroups();
  }

  async function submitGitLabAccessToken(): Promise<void> {
    if (!gitlabAccessToken.trim()) {
      gitlabTokenError = 'Please enter an access token';
      return;
    }

    if (!selectedGitLabGroup) {
      gitlabTokenError = 'No group selected';
      return;
    }

    try {
      isSubmittingGitLabToken = true;
      gitlabTokenError = null;
      // Use the selected group ID as the installation ID
      await api.submitGitLabAccessToken(selectedGitLabGroup.id.toString(), gitlabAccessToken);
      gitlabTokenSubmitted = true;
      markGitLabStepComplete('submit-token');
    } catch (error) {
      console.error('Failed to submit access token:', error);
      gitlabTokenError = 'Failed to submit access token. Please verify it is valid and try again.';
    } finally {
      isSubmittingGitLabToken = false;
    }
  }

  async function submitGitLabDemoAccessToken(): Promise<void> {
    if (!gitlabAccessToken.trim()) {
      gitlabTokenError = 'Please enter an access token';
      return;
    }

    if (!selectedGitLabDemoGroup) {
      gitlabTokenError = 'No group selected';
      return;
    }

    try {
      isSubmittingGitLabToken = true;
      gitlabTokenError = null;
      // Use the selected demo group ID as the installation ID
      await api.submitGitLabAccessToken(selectedGitLabDemoGroup.id.toString(), gitlabAccessToken);
      gitlabTokenSubmitted = true;
      markGitLabDemoStepComplete('submit-token');
    } catch (error) {
      console.error('Failed to submit access token:', error);
      gitlabTokenError = 'Failed to submit access token. Please verify it is valid and try again.';
    } finally {
      isSubmittingGitLabToken = false;
    }
  }

  async function verifyWebhook(): Promise<void> {
    if (!selectedGitLabGroup) return;

    try {
      checkingWebhook = true;
      webhookVerificationError = null;

      const config = await api.getGitLabWebhookConfig(selectedGitLabGroup.id.toString());
      const isActive = config.state === 'installed';

      if (isActive) {
        webhookVerificationError = null;
        markGitLabStepComplete('configure-webhook');
      } else {
        webhookVerificationError = 'Webhook is not active yet. Please test it with a Push Event in GitLab.';
      }
    } catch (error) {
      console.error('Failed to check webhook:', error);
      webhookVerificationError = 'Unable to verify webhook. Please ensure you\'ve added it and tested with a Push Event.';
    } finally {
      checkingWebhook = false;
    }
  }

</script>

<PageLayout activeItem="getting-started" title="Getting Started">
  <div class="max-w-4xl mx-auto px-4 py-8">

    <!-- Progress Bar -->
    <div class="mb-8">
      <div class="flex items-center justify-between mb-2">
        <span class="text-sm font-medium text-[var(--sg-text)]">Setup Progress</span>
        <span class="text-sm text-[var(--sg-text-dim)]">
          {#if currentStep === 'assessment'}
            Analyzing your setup...
          {:else if currentStep === 'path-selection'}
            Choose your path
          {:else if currentStep === 'github-demo-setup'}
            GitHub demo setup
          {:else if currentStep === 'gitlab-demo-setup'}
            GitLab demo setup
          {:else if currentStep === 'github-repo-setup'}
            GitHub repository setup
          {:else if currentStep === 'gitlab-setup'}
            GitLab setup
          {:else if currentStep === 'validation'}
            Validating setup
          {:else}
            Complete!
          {/if}
        </span>
      </div>
      <div class="w-full bg-[var(--sg-bg-2)] rounded-full h-2">
        <div
          class="bg-[var(--sg-accent-button)] h-2 rounded-full transition-all duration-300 {
            currentStep === 'assessment' ? 'w-[10%]' :
            currentStep === 'path-selection' ? 'w-1/4' :
            currentStep === 'github-demo-setup' || currentStep === 'gitlab-demo-setup' || currentStep === 'github-repo-setup' || currentStep === 'gitlab-setup' ? 'w-[60%]' :
            currentStep === 'validation' ? 'w-4/5' :
            'w-full'
          }"
        ></div>
      </div>
    </div>

    <!-- Header -->
    <div class="text-center mb-6 sm:mb-8">
      <img src="/assets/images/logo-symbol.svg" alt="Terrateam" class="w-10 h-10 sm:w-12 sm:h-12 mx-auto mb-3 sm:mb-4" />
      <h1 class="text-2xl sm:text-3xl font-bold mb-2 text-[var(--sg-accent)]">Getting Started with Terrateam</h1>
      <p class="text-sm sm:text-base text-[var(--sg-text-dim)]">We'll help you set up Terraform automation in minutes</p>
    </div>

    <!-- Wizard Content -->
    <div class="bg-[var(--sg-bg-1)] rounded-lg border border-[var(--sg-border)] p-4 sm:p-6">

      {#if currentStep === 'assessment'}
        <!-- Assessment Step -->
        <div class="text-center py-8 sm:py-12">
          <div class="inline-flex items-center justify-center w-14 h-14 sm:w-16 sm:h-16 bg-[var(--sg-accent-bg)] rounded-full mb-4 sm:mb-6">
            <Icon icon="mdi:magnify" class="text-[var(--sg-accent)]" width="28" />
          </div>
          <h2 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)] mb-2">Analyzing Your Setup</h2>
          <p class="text-sm sm:text-base text-[var(--sg-text-dim)] mb-4 sm:mb-6">We're checking your current Terrateam configuration...</p>

          {#if isLoadingAssessment}
            <div class="flex items-center justify-center">
              <LoadingSpinner size="lg" centered={false} />
            </div>
          {:else if assessmentError}
            <div class="bg-[var(--sg-warning-bg)] border border-[var(--sg-warning)] rounded-lg p-4">
              <p class="text-[var(--sg-warning)] text-sm">{assessmentError}</p>
            </div>
          {/if}
        </div>

      {:else if currentStep === 'path-selection'}
        <!-- Path Selection Step -->
        <div class="mb-6">
            <h2 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)] mb-4">Choose Your Setup Path</h2>

            <!-- Assessment Results -->
            {#if !assessmentError}
              <div class="bg-[var(--sg-accent-bg)] rounded-lg p-3 sm:p-4 mb-4 sm:mb-6">
                <h3 class="font-medium text-[var(--sg-accent)] mb-2">What we found:</h3>
                <div class="space-y-1 text-sm text-[var(--sg-accent)]">
                  <div class="flex items-center">
                    <Icon icon={hasInstallations ? "mdi:check" : "mdi:close"}
                                  class={hasInstallations ? "text-[var(--sg-success)]" : "text-[var(--sg-text-dim)]"}
                                  width="16" />
                    <span class="ml-2">
                      {hasInstallations ? `Found ${installations.length} ${VCS_PROVIDERS[currentProvider].displayName} installation${installations.length > 1 ? 's' : ''}` : `No ${VCS_PROVIDERS[currentProvider].displayName} installations found`}
                    </span>
                  </div>
                  <div class="flex items-center">
                    <Icon icon={hasConfiguredRepos ? "mdi:check" : "mdi:close"}
                                  class={hasConfiguredRepos ? "text-[var(--sg-success)]" : "text-[var(--sg-text-dim)]"}
                                  width="16" />
                    <span class="ml-2">
                      {hasConfiguredRepos ? 'Found configured repositories' : 'No configured repositories found'}
                    </span>
                  </div>
                </div>

                {#if recommendedPath === 'demo'}
                  <p class="mt-3 text-sm font-medium text-[var(--sg-accent)] flex items-center">
                    <Icon icon="mdi:lightbulb" class="text-[var(--sg-warning)] mr-2" width="16" />
                  We recommend starting with the demo to learn how Terrateam works
                </p>
              {:else}
                <p class="mt-3 text-sm font-medium text-[var(--sg-accent)] flex items-center">
                  <Icon icon="mdi:lightbulb" class="text-[var(--sg-warning)] mr-2" width="16" />
                  We recommend setting up your existing repository
                </p>
              {/if}
            </div>
          {/if}
        </div>

        <!-- Path Options -->
        <div class="grid md:grid-cols-2 gap-4 sm:gap-6">
          <!-- Demo Path -->
          <button
            on:click={() => selectPath('demo')}
            class="text-left p-4 sm:p-6 border-2 border-[var(--sg-border)] rounded-lg hover:border-[var(--sg-accent)] transition-colors {recommendedPath === 'demo' ? 'ring-2 ring-[var(--sg-accent)] border-[var(--sg-accent)]' : ''}"
          >
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center justify-center w-10 h-10 bg-[var(--sg-success-bg)] rounded-lg">
                <Icon icon="mdi:flash" class="text-[var(--sg-success)]" width="20" />
              </div>
              {#if recommendedPath === 'demo'}
                <span class="bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] text-xs px-2 py-1 rounded-full font-medium">Recommended</span>
              {/if}
            </div>

            <h3 class="text-lg font-semibold text-[var(--sg-text)] mb-2">Try the Demo</h3>
            <p class="text-[var(--sg-text-dim)] text-sm mb-4">
              Learn Terrateam with a safe sandbox environment. No cloud credentials needed.
            </p>

            <div class="space-y-2">
              <div class="flex items-center text-sm text-[var(--sg-text-dim)]">
                <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                No cloud setup required
              </div>
              <div class="flex items-center text-sm text-[var(--sg-text-dim)]">
                <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                See Terraform plans instantly
              </div>
              <div class="flex items-center text-sm text-[var(--sg-text-dim)]">
                <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                2-3 minutes to complete
              </div>
            </div>
          </button>

          <!-- Repository Path -->
          <button
            on:click={() => selectPath('repo')}
            class="text-left p-4 sm:p-6 border-2 border-[var(--sg-border)] rounded-lg hover:border-[var(--sg-accent)] transition-colors {recommendedPath === 'repo' ? 'ring-2 ring-[var(--sg-accent)] border-[var(--sg-accent)]' : ''}"
          >
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center justify-center w-10 h-10 bg-[var(--sg-accent-bg)] rounded-lg">
                <Icon icon="mdi:source-repository" class="text-[var(--sg-accent)]" width="20" />
              </div>
              {#if recommendedPath === 'repo'}
                <span class="bg-[var(--sg-accent-bg)] text-[var(--sg-accent)] text-xs px-2 py-1 rounded-full font-medium">Recommended</span>
              {/if}
            </div>

            <h3 class="text-lg font-semibold text-[var(--sg-text)] mb-2">Connect Your Repository</h3>
            <p class="text-[var(--sg-text-dim)] text-sm mb-4">
              Set up Terrateam with your existing Terraform code and real infrastructure.
            </p>

            <div class="space-y-2">
              <div class="flex items-center text-sm text-[var(--sg-text-dim)]">
                <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                Works with existing repos
              </div>
              <div class="flex items-center text-sm text-[var(--sg-text-dim)]">
                <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                Real infrastructure automation
              </div>
              <div class="flex items-center text-sm text-[var(--sg-text-dim)]">
                <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                5-10 minutes to complete
              </div>
            </div>
          </button>
        </div>

      {:else if currentStep === 'github-demo-setup'}
        <!-- GitHub Demo Setup Wizard -->
        <div class="mb-6">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
            <h2 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)]">GitHub Demo Setup</h2>
            <button
              on:click={goBack}
              class="text-xs md:text-sm text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] flex items-center self-start sm:self-auto"
            >
              <Icon icon="mdi:arrow-left" class="mr-1" width="16" />
              Back
            </button>
          </div>

          <!-- Demo Steps Progress -->
          <div class="mb-8">
            <div class="flex items-center justify-between mb-4">
              {#each (currentProvider === 'gitlab' ? [
                {step: 'fork', index: 0, label: '1'},
                {step: 'enable-pipelines', index: 1, label: '2'},
                {step: 'make-changes', index: 2, label: '4'},
                {step: 'success', index: 3, label: '5'}
              ] : [
                {step: 'install-app', index: 0, label: '1'},
                {step: 'fork', index: 1, label: '2'},
                {step: 'enable-actions', index: 2, label: '3'},
                {step: 'make-changes', index: 3, label: '4'},
                {step: 'success', index: 4, label: '5'}
              ]) as stepInfo}
                <div class="flex items-center {stepInfo.index < 4 ? 'flex-1' : ''}">
                  <div class="flex items-center justify-center w-8 h-8 sm:w-10 sm:h-10 rounded-full text-xs sm:text-sm font-medium
                              {currentDemoStep === stepInfo.step ? 'bg-[var(--sg-accent-button)] text-white' :
                               (stepInfo.step === 'fork' && demoStepCompleted.fork) ||
                               (stepInfo.step === 'enable-actions' && demoStepCompleted['enable-actions']) ||
                               (stepInfo.step === 'install-app' && demoStepCompleted['install-app']) ||
                               (stepInfo.step === 'make-changes' && demoStepCompleted['make-changes'])
                               ? 'bg-[var(--sg-success)] text-white' :
                               'bg-[var(--sg-bg-2)] text-[var(--sg-text-dim)]'}">
                    {#if (stepInfo.step === 'fork' && demoStepCompleted.fork) ||
                         (stepInfo.step === 'enable-actions' && demoStepCompleted['enable-actions']) ||
                         (stepInfo.step === 'install-app' && demoStepCompleted['install-app']) ||
                         (stepInfo.step === 'make-changes' && demoStepCompleted['make-changes'])}
                      <Icon icon="mdi:check" class="text-white" width="16" />
                    {:else}
                      {stepInfo.label}
                    {/if}
                  </div>
                  {#if stepInfo.index < 4}
                    <div class="flex-1 h-1 mx-2 {
                      (stepInfo.step === 'fork' && demoStepCompleted.fork) ||
                      (stepInfo.step === 'enable-actions' && demoStepCompleted['enable-actions']) ||
                      (stepInfo.step === 'install-app' && demoStepCompleted['install-app']) ||
                      (stepInfo.step === 'make-changes' && demoStepCompleted['make-changes'])
                      ? 'bg-[var(--sg-success)]' : 'bg-[var(--sg-bg-2)]'}"></div>
                  {/if}
                </div>
              {/each}
            </div>
            <div class="text-center text-xs sm:text-sm text-[var(--sg-text-dim)]">
              Step {['install-app', 'fork', 'enable-actions', 'make-changes', 'success'].indexOf(currentDemoStep) + 1} of 5
            </div>
          </div>

          <!-- Step Content -->
          {#if currentDemoStep === 'install-app'}
            <div class="bg-[var(--sg-success-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-success)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:download" class="text-white" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-success)] mb-2 text-center sm:text-left">Step 1: Install Terrateam GitHub App</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-success)] mb-4 text-center sm:text-left">
                    Install the Terrateam GitHub App on your organization to enable Terraform automation.
                  </p>

                  {#if hasInstallations}
                    <div class="bg-[var(--sg-success-bg)] rounded-lg p-3 sm:p-4 mb-4 border border-[var(--sg-success)]">
                      <div class="flex items-start sm:items-center">
                        <Icon icon="mdi:check-circle" class="text-[var(--sg-success)] mr-2 flex-shrink-0 mt-0.5 sm:mt-0" width="20" />
                        <span class="text-xs sm:text-sm text-[var(--sg-success)] font-medium">
                          Great! We detected {installations.length} GitHub installation{installations.length > 1 ? 's' : ''}.
                        </span>
                      </div>
                    </div>
                  {:else}
                    <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-success)]">
                      <div class="flex items-center justify-between">
                        <div>
                          <div class="font-medium text-[var(--sg-text)]">Terrateam GitHub App</div>
                          <div class="text-sm text-[var(--sg-text-dim)]">Enables Terraform automation in your repositories</div>
                        </div>
                        <Icon icon="mdi:github" class="text-[var(--sg-text-dim)]" width="24" />
                      </div>
                    </div>
                  {/if}

                  <div class="bg-[var(--sg-accent-bg)] rounded-lg p-3 sm:p-4 mb-4 border border-[var(--sg-accent)]">
                    <div class="flex items-start">
                      <Icon icon="mdi:information" class="text-[var(--sg-accent)] mr-2 mt-0.5 flex-shrink-0" width="20" />
                      <div class="text-xs sm:text-sm text-[var(--sg-accent)]">
                        <p class="font-medium mb-1">Demo in a different organization?</p>
                        <p>You can install the app on any organization where you want to run the demo.</p>
                      </div>
                    </div>
                  </div>

                  <div class="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
                    <button
                      on:click={() => openExternalLink(githubAppUrl, 'github_app_install')}
                      class="bg-[var(--sg-success)] hover:bg-[var(--sg-success)] text-white px-4 py-2.5 rounded-lg text-sm font-medium flex items-center justify-center"
                    >
                      <Icon icon="mdi:download" class="mr-2" width="16" />
                      Install GitHub App
                    </button>
                    <button
                      on:click={checkAppInstallation}
                      disabled={checkingAppInstallation}
                      class="border border-[var(--sg-success)] text-[var(--sg-success)] px-4 py-2.5 rounded-lg text-sm font-medium hover:bg-[var(--sg-success-bg)] disabled:opacity-50 flex items-center justify-center"
                    >
                      {#if checkingAppInstallation}
                        <Icon icon="mdi:loading" class="animate-spin mr-2" width="16" />
                        Checking...
                      {:else if hasInstallations}
                        Continue
                      {:else}
                        Check Installation
                      {/if}
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentDemoStep === 'fork'}
            <div class="bg-[var(--sg-accent-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-accent-button)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:source-fork" class="text-white" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-accent)] mb-2 text-center sm:text-left">Step 2: Fork the Demo Repository</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-accent)] mb-4 text-center sm:text-left">
                    Fork our demo repository to your GitHub account. This gives you your own copy to experiment with.
                  </p>

                  <div class="bg-[var(--sg-bg-1)] rounded-lg p-3 sm:p-4 mb-4 border border-[var(--sg-accent)]">
                    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
                      <div class="flex-1 min-w-0">
                        <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base">terrateam-demo/kick-the-tires</div>
                        <div class="text-xs sm:text-sm text-[var(--sg-text-dim)]">Safe demo repository with null resources</div>
                      </div>
                      <Icon icon="mdi:github" class="text-[var(--sg-text-dim)] hidden sm:block flex-shrink-0" width="24" />
                    </div>
                  </div>

                  <div class="flex flex-col sm:flex-row gap-3">
                    <button
                      on:click={() => {
                        const repoUrl = currentProvider === 'gitlab'
                          ? 'https://gitlab.com/terrateam-demo/kick-the-tires'
                          : 'https://github.com/terrateam-demo/kick-the-tires';
                        openExternalLink(repoUrl);
                      }}
                      class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-4 py-2.5 rounded-lg text-sm font-medium flex items-center justify-center"
                    >
                      <Icon icon="mdi:source-fork" class="mr-2" width="16" />
                      Fork {terminology.repository}
                    </button>
                    <button
                      on:click={() => markDemoStepComplete('fork')}
                      class="border border-[var(--sg-accent)] text-[var(--sg-accent)] px-4 py-2.5 rounded-lg text-sm font-medium hover:bg-[var(--sg-accent-bg)]"
                    >
                      I've forked it
                    </button>
                    <button
                      on:click={() => goToDemoStep('install-app')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2.5 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentDemoStep === 'enable-actions'}
            <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-warning)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:play-circle" class="text-white" width="20" />
                  </div>
                </div>
                <div class="ml-4 flex-1">
                  <h3 class="text-lg font-semibold text-[var(--sg-warning)] mb-2">Step 3: Enable GitHub Actions</h3>
                  <p class="text-[var(--sg-warning)] mb-4">
                    Forked repositories disable workflows by default for security. Let's enable them.
                  </p>

                  <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-warning)]">
                    <div class="space-y-2 text-sm">
                      <div class="flex items-center">
                        <Icon icon="mdi:numeric-1-circle" class="text-[var(--sg-warning)] mr-2" width="16" />
                        <span class="text-[var(--sg-text-muted)]">Go to your forked repository</span>
                      </div>
                      <div class="flex items-center">
                        <Icon icon="mdi:numeric-2-circle" class="text-[var(--sg-warning)] mr-2" width="16" />
                        <span class="text-[var(--sg-text-muted)]">Click the <strong>Actions</strong> tab</span>
                      </div>
                      <div class="flex items-center">
                        <Icon icon="mdi:numeric-3-circle" class="text-[var(--sg-warning)] mr-2" width="16" />
                        <span class="text-[var(--sg-text-muted)]">Click <strong>"I understand my workflows, go ahead and enable them"</strong></span>
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markDemoStepComplete('enable-actions')}
                      class="bg-[var(--sg-warning)] hover:bg-[var(--sg-warning)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                    >
                      Actions Enabled
                    </button>
                    <button
                      on:click={() => goToDemoStep('fork')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentDemoStep === 'make-changes'}
            <div class="bg-[var(--sg-purple-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-purple)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:file-edit" class="text-white" width="20" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)] mb-3 text-center sm:text-left">Step 4: Make Your First Change</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-purple)] mb-6 text-center sm:text-left">
                    Now let's make a change to see Terrateam in action! We'll edit a file and create a pull request.
                  </p>

                  <div class="bg-[var(--sg-purple-bg)] rounded-lg p-4 sm:p-5 mb-4 border border-[var(--sg-purple)]">
                    <div class="space-y-6">
                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-purple)] rounded-full flex items-center justify-center text-white text-sm font-bold">1</div>
                        </div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] mb-2 text-sm sm:text-base text-center sm:text-left">Edit <code class="bg-[var(--sg-purple-bg)] px-1.5 py-0.5 rounded text-xs font-mono">dev/main.tf</code></div>
                          <div class="text-[var(--sg-text-dim)] text-xs sm:text-sm leading-relaxed text-center sm:text-left">
                            Change <code class="bg-[var(--sg-purple-bg)] px-1.5 py-0.5 rounded text-xs font-mono break-all">null_resource_count = 0</code> to <code class="bg-[var(--sg-purple-bg)] px-1.5 py-0.5 rounded text-xs font-mono break-all">null_resource_count = 1</code>
                          </div>
                        </div>
                      </div>
                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-purple)] rounded-full flex items-center justify-center text-white text-sm font-bold">2</div>
                        </div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base text-center sm:text-left">Create a new branch and push your changes</div>
                        </div>
                      </div>
                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-purple)] rounded-full flex items-center justify-center text-white text-sm font-bold">3</div>
                        </div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base text-center sm:text-left">Open a pull request</div>
                        </div>
                      </div>
                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-purple)] rounded-full flex items-center justify-center text-white text-sm font-bold">4</div>
                        </div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base text-center sm:text-left">Watch Terrateam automatically comment with the plan!</div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="bg-[var(--sg-accent-bg)] rounded-lg p-3 sm:p-4 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:lightbulb" class="text-[var(--sg-accent)] mr-2 mt-0.5 flex-shrink-0" width="18" />
                      <div class="text-xs sm:text-sm text-[var(--sg-accent)]">
                        <strong>Pro tip:</strong> When you're ready to apply the changes, comment <code class="bg-[var(--sg-accent-bg)] px-1.5 py-0.5 rounded text-xs">terrateam apply</code> on your PR.
                      </div>
                    </div>
                  </div>

                  <div class="flex flex-col sm:flex-row gap-3">
                    <button
                      on:click={() => markDemoStepComplete('make-changes')}
                      class="bg-[var(--sg-purple)] hover:opacity-90 text-white px-4 py-2.5 rounded-lg text-sm font-medium"
                    >
                      I've created a PR
                    </button>
                    <button
                      on:click={() => goToDemoStep('enable-actions')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2.5 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentDemoStep === 'success'}
            <div class="text-center py-12">
              <div class="inline-flex items-center justify-center w-16 h-16 bg-[var(--sg-success-bg)] rounded-full mb-6">
                <Icon icon="mdi:check-circle" class="text-[var(--sg-success)]" width="32" />
              </div>
              <h3 class="text-2xl font-semibold text-[var(--sg-text)] mb-2 flex items-center justify-center">
                <Icon icon="mdi:party-popper" class="text-[var(--sg-purple)] mr-2" width="28" />
                Demo Complete!
              </h3>
              <p class="text-[var(--sg-text-dim)] mb-6">
                You've successfully set up the Terrateam demo and seen how Terraform automation works with pull requests.
              </p>

              <div class="bg-[var(--sg-success-bg)] rounded-lg p-6 mb-6 max-w-md mx-auto">
                <h4 class="font-semibold text-[var(--sg-success)] mb-3">What you've learned:</h4>
                <div class="space-y-2 text-sm text-[var(--sg-success)]">
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                    How to set up Terrateam with GitHub
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                    Automatic Terraform plans on PRs
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                    How to apply changes with commands
                  </div>
                </div>
              </div>

              <div class="flex justify-center space-x-4">
                <button
                  on:click={() => {currentStep = 'path-selection'; selectedPath = null; currentDemoStep = 'install-app';}}
                  class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-6 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                >
                  Start Over
                </button>
                <button
                  on:click={() => selectPath('repo')}
                  class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-6 py-2 rounded-lg text-sm font-medium"
                >
                  Set Up My Repository
                </button>
              </div>
            </div>
          {/if}
        </div>

      {:else if currentStep === 'gitlab-demo-setup'}
        <!-- GitLab Demo Setup Wizard -->
        <div class="mb-6">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
            <h2 class="text-xl sm:text-2xl font-semibold text-[var(--sg-text)] text-center sm:text-left">GitLab Demo Setup</h2>
            <button
              on:click={goBack}
              class="text-sm text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] flex items-center justify-center sm:justify-start"
            >
              <Icon icon="mdi:arrow-left" class="mr-1" width="16" />
              Back
            </button>
          </div>

          <!-- GitLab Demo Steps Progress -->
          <div class="mb-8">
            <div class="grid grid-cols-7 gap-1 mb-4 px-1">
              {#each [
                {step: 'select-group', index: 0, label: '1'},
                {step: 'fork', index: 1, label: '2'},
                {step: 'submit-token', index: 2, label: '3'},
                {step: 'configure-webhook', index: 3, label: '4'},
                {step: 'configure-variables', index: 4, label: '5'},
                {step: 'make-changes', index: 5, label: '6'},
                {step: 'success', index: 6, label: '7'}
              ] as stepInfo}
                <div class="flex justify-center">
                  <div class="flex items-center justify-center w-8 h-8 rounded-full text-xs font-medium
                              {currentGitLabDemoStep === stepInfo.step ? 'bg-[var(--sg-accent-button)] text-white' :
                               (stepInfo.step === 'select-group' && gitlabDemoStepCompleted['select-group']) ||
                               (stepInfo.step === 'fork' && gitlabDemoStepCompleted.fork) ||
                               (stepInfo.step === 'submit-token' && gitlabDemoStepCompleted['submit-token']) ||
                               (stepInfo.step === 'configure-webhook' && gitlabDemoStepCompleted['configure-webhook']) ||
                               (stepInfo.step === 'configure-variables' && gitlabDemoStepCompleted['configure-variables']) ||
                               (stepInfo.step === 'make-changes' && gitlabDemoStepCompleted['make-changes'])
                               ? 'bg-[var(--sg-success)] text-white' :
                               'bg-[var(--sg-bg-2)] text-[var(--sg-text-dim)]'}">
                    {#if (stepInfo.step === 'select-group' && gitlabDemoStepCompleted['select-group']) ||
                         (stepInfo.step === 'fork' && gitlabDemoStepCompleted.fork) ||
                         (stepInfo.step === 'submit-token' && gitlabDemoStepCompleted['submit-token']) ||
                         (stepInfo.step === 'configure-webhook' && gitlabDemoStepCompleted['configure-webhook']) ||
                         (stepInfo.step === 'configure-variables' && gitlabDemoStepCompleted['configure-variables']) ||
                         (stepInfo.step === 'make-changes' && gitlabDemoStepCompleted['make-changes'])}
                      <Icon icon="mdi:check" width="16" />
                    {:else}
                      {stepInfo.label}
                    {/if}
                  </div>
                </div>
              {/each}
            </div>
            <div class="text-center text-xs sm:text-sm text-[var(--sg-text-dim)]">
              Step {['select-group', 'fork', 'submit-token', 'configure-webhook', 'configure-variables', 'make-changes', 'success'].indexOf(currentGitLabDemoStep) + 1} of 7
            </div>
          </div>

          <!-- GitLab Demo Step Content -->
          {#if currentGitLabDemoStep === 'select-group'}
            <div class="bg-[var(--sg-accent-bg)] rounded-lg p-4 sm:p-6">
              <div class="mb-6">
                <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-accent)] mb-3 text-center sm:text-left">
                  Select a GitLab Group
                </h3>
                <p class="text-sm sm:text-base text-[var(--sg-accent)] text-center sm:text-left">
                  Choose which GitLab group you'll use for the demo. You'll fork the demo project into this group.
                </p>
              </div>

              {#if isLoadingGitLabGroups}
                <div class="flex justify-center py-8">
                  <LoadingSpinner size="lg" centered={false} />
                </div>
              {:else if gitlabGroupsError}
                <div class="bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-lg p-4 mb-4">
                  <p class="text-[var(--sg-error)] text-sm">{gitlabGroupsError}</p>
                </div>
                <button
                  on:click={loadGitLabGroups}
                  class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                >
                  Try Again
                </button>
              {:else if gitlabDemoGroups.length === 0}
                <div class="bg-[var(--sg-warning-bg)] border border-[var(--sg-warning)] rounded-lg p-4">
                  <div class="flex items-start">
                    <Icon icon="mdi:alert" class="text-[var(--sg-warning)] mr-2 mt-0.5" width="20" />
                    <div>
                      <p class="text-[var(--sg-warning)] text-sm font-medium mb-1">
                        No GitLab groups found
                      </p>
                      <p class="text-[var(--sg-warning)] text-xs">
                        Terrateam requires a GitLab group to operate. Personal namespaces are not supported.
                        Please create a group or ask to be added to an existing group first.
                      </p>
                    </div>
                  </div>
                </div>
              {:else}
                <div class="space-y-2 max-h-64 overflow-y-auto">
                  {#each gitlabDemoGroups as group}
                    <button
                      on:click={() => selectGitLabDemoGroup(group)}
                      class="w-full text-left p-3 rounded-lg border transition-colors
                             {selectedGitLabDemoGroup?.id === group.id
                               ? 'border-[var(--sg-accent)] bg-[var(--sg-accent-bg)]'
                               : 'border-[var(--sg-border)] hover:border-[var(--sg-accent)] hover:bg-[var(--sg-bg-2)]'}"
                    >
                      <div class="flex items-center">
                        <Icon icon="mdi:folder-account" class="text-[var(--sg-accent)] mr-3" width="20" />
                        <span class="font-medium text-[var(--sg-text)]">{group.name}</span>
                      </div>
                    </button>
                  {/each}
                </div>
              {/if}
            </div>

          {:else if currentGitLabDemoStep === 'fork'}
            <div class="bg-[var(--sg-accent-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="flex items-center justify-center w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-accent-bg)] rounded-lg">
                    <Icon icon="mdi:source-fork" class="text-[var(--sg-accent)]" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-accent)] mb-3 text-center sm:text-left">
                    Fork the Demo Project
                  </h3>
                  <p class="text-sm sm:text-base text-[var(--sg-accent)] mb-6 text-center sm:text-left">
                    Fork our demo GitLab project to {selectedGitLabDemoGroup ? `the ${selectedGitLabDemoGroup.name} group` : 'your account'}. This contains a simple Terraform configuration you can experiment with safely.
                  </p>

                  <div class="space-y-6">
                    <div>
                      <button
                        on:click={() => openExternalLink('https://gitlab.com/terrateam-demo/kick-the-tires')}
                        class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-6 py-3 rounded-lg text-sm font-medium flex items-center justify-center w-full sm:w-auto"
                      >
                        <Icon icon="mdi:source-fork" class="mr-2" width="16" />
                        Fork Project
                      </button>
                    </div>

                    <div class="bg-[var(--sg-accent-bg)] rounded-lg p-4">
                      <label for="forked-project-path" class="block text-sm font-medium text-[var(--sg-accent)] mb-2">
                        After forking, enter your project path:
                      </label>
                      <input
                        id="forked-project-path"
                        type="text"
                        bind:value={forkedProjectPath}
                        placeholder="groupname/kick-the-tires"
                        class="w-full px-3 py-2 border border-[var(--sg-accent)] rounded-lg bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder-[var(--sg-text-dim)] focus:outline-none focus:ring-2 focus:ring-[var(--sg-accent)]"
                      />
                    </div>

                    <button
                      on:click={() => {
                        if (forkedProjectPath.trim()) {
                          markGitLabDemoStepComplete('fork');
                        } else {
                          alert('Please enter your forked project path');
                        }
                      }}
                      class="border border-[var(--sg-accent)] text-[var(--sg-accent)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-accent-bg)]"
                    >
                      Continue
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabDemoStep === 'submit-token'}
            <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-warning)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:key" class="text-white" width="20" />
                  </div>
                </div>
                <div class="ml-4 flex-1">
                  <h3 class="text-lg font-semibold text-[var(--sg-warning)] mb-2">Submit GitLab Access Token</h3>
                  <p class="text-[var(--sg-warning)] mb-4">
                    Terrateam uses this token to call the GitLab API on behalf of your group. Choose the most narrowly-scoped token that fits your setup.
                  </p>

                  <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-warning)]">
                    <GitLabTokenInstructions
                      webBaseUrl={serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}
                      groupName={selectedGitLabDemoGroup?.name || null}
                      projectPath={forkedProjectPath || null}
                    />
                  </div>

                  <div class="mb-4">
                    <label for="gitlab-demo-access-token" class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
                      Access Token
                    </label>
                    <input
                      id="gitlab-demo-access-token"
                      type="password"
                      bind:value={gitlabAccessToken}
                      placeholder="Enter your GitLab access token"
                      class="w-full px-4 py-2 border border-[var(--sg-border)] rounded-lg
                             bg-[var(--sg-bg-1)] text-[var(--sg-text)]
                             focus:ring-2 focus:ring-[var(--sg-warning)] focus:border-[var(--sg-warning)]
                             disabled:opacity-50 disabled:cursor-not-allowed"
                      disabled={isSubmittingGitLabToken || gitlabTokenSubmitted}
                    />
                  </div>

                  {#if gitlabTokenError}
                    <div class="bg-[var(--sg-error-bg)] rounded p-3 mb-4">
                      <div class="flex items-start">
                        <Icon icon="mdi:alert-circle" class="text-[var(--sg-error)] mr-2 mt-0.5" width="16" />
                        <div class="text-sm text-[var(--sg-error)]">{gitlabTokenError}</div>
                      </div>
                    </div>
                  {/if}

                  {#if gitlabTokenSubmitted}
                    <div class="bg-[var(--sg-success-bg)] rounded p-3 mb-4">
                      <div class="flex items-start">
                        <Icon icon="mdi:check-circle" class="text-[var(--sg-success)] mr-2 mt-0.5" width="16" />
                        <div class="text-sm text-[var(--sg-success)]">
                          <strong>Success!</strong> Access token submitted successfully.
                        </div>
                      </div>
                    </div>
                  {/if}

                  <div class="flex items-center justify-end space-x-3">
                    <button
                      on:click={() => goToGitLabDemoStep('fork')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                    <button
                      on:click={submitGitLabDemoAccessToken}
                      disabled={isSubmittingGitLabToken || gitlabTokenSubmitted || !gitlabAccessToken.trim()}
                      class="bg-[var(--sg-warning)] hover:bg-[var(--sg-warning)] text-white px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed flex items-center"
                    >
                      {#if isSubmittingGitLabToken}
                        <LoadingSpinner size="sm" color="white" centered={false} />
                        <span class="ml-2">Submitting...</span>
                      {:else if gitlabTokenSubmitted}
                        <Icon icon="mdi:check" class="mr-2" width="16" />
                        Submitted
                      {:else}
                        Submit Token
                      {/if}
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabDemoStep === 'configure-webhook'}
            <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="flex items-center justify-center w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-warning-bg)] rounded-lg">
                    <Icon icon="mdi:webhook" class="text-[var(--sg-warning)]" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-warning)] mb-3 text-center sm:text-left">
                    Configure Webhook
                  </h3>
                  <p class="text-sm sm:text-base text-[var(--sg-warning)] mb-6 text-center sm:text-left">
                    Add a webhook to your forked project so Terrateam can respond to merge requests and code changes.
                  </p>

                  <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 sm:p-5 mb-4">
                    <h4 class="font-semibold text-[var(--sg-warning)] mb-3 text-center sm:text-left">Instructions:</h4>
                    <ol class="list-decimal list-inside space-y-3 text-sm text-[var(--sg-warning)]">
                      <li>
                        <a
                          href="{serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}/{forkedProjectPath}/-/hooks"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="inline-flex items-center font-medium text-[var(--sg-warning)] underline hover:text-[var(--sg-warning)] break-words"
                        >
                          <span>Open your project webhooks</span>
                          <Icon icon="mdi:open-in-new" class="ml-1 flex-shrink-0" width="16" />
                        </a>
                      </li>
                      <li>Click <strong>Add new webhook</strong></li>
                      <li>URL: <code class="bg-[var(--sg-warning-bg)] px-1 rounded text-xs break-all">{webhookUrl || 'Loading...'}</code></li>
                      <li>Secret token: <code class="bg-[var(--sg-warning-bg)] px-1 rounded text-xs break-all">{webhookSecret || 'Loading...'}</code></li>
                      <li>Enable these triggers:
                        <ul class="list-disc list-inside ml-4 mt-1">
                          <li>Push events</li>
                          <li>Comments</li>
                          <li>Merge request events</li>
                        </ul>
                      </li>
                      <li>Click <strong>Add webhook</strong></li>
                      <li>Find the new Terrateam webhook in the list and click <strong>Test</strong> → <strong>Push events</strong> to activate it</li>
                      <li>Click <strong>Verify Webhook</strong> below</li>
                    </ol>
                  </div>

                  {#if webhookVerificationError}
                    <div class="bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-lg p-4 mb-4">
                      <div class="flex items-start">
                        <Icon icon="mdi:alert-circle" class="text-[var(--sg-error)] mr-2 mt-0.5" width="20" />
                        <p class="text-sm text-[var(--sg-error)]">{webhookVerificationError}</p>
                      </div>
                    </div>
                  {/if}

                  <div class="flex flex-col sm:flex-row gap-3">
                    <button
                      on:click={checkWebhook}
                      disabled={checkingWebhook}
                      class="bg-[var(--sg-warning)] hover:bg-[var(--sg-warning)] text-white px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center w-full sm:w-auto"
                    >
                      {#if checkingWebhook}
                        <svg class="w-4 h-4 mr-2 animate-spin" fill="none" viewBox="0 0 24 24">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
                        </svg>
                        Checking...
                      {:else}
                        <Icon icon="mdi:check" class="mr-2" width="16" />
                        Verify Webhook
                      {/if}
                    </button>
                    <button
                      on:click={() => markGitLabDemoStepComplete('configure-webhook')}
                      class="border border-[var(--sg-warning)] text-[var(--sg-warning)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-warning-bg)] w-full sm:w-auto text-center"
                    >
                      Skip Verification
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabDemoStep === 'configure-variables'}
            <div class="bg-[var(--sg-purple-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="flex items-center justify-center w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-purple-bg)] rounded-lg">
                    <Icon icon="mdi:cog" class="text-[var(--sg-purple)]" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)] mb-3 text-center sm:text-left">
                    Configure CI/CD Variables
                  </h3>
                  <p class="text-sm sm:text-base text-[var(--sg-purple)] mb-6 text-center sm:text-left">
                    Configure project settings to allow Terrateam to pass credentials securely to your Terraform runs.
                  </p>

                  <div class="bg-[var(--sg-purple-bg)] rounded-lg p-4 sm:p-5 mb-4">
                    <h4 class="font-semibold text-[var(--sg-text)] mb-3 text-center sm:text-left">Instructions:</h4>
                    <ol class="list-decimal list-inside space-y-3 text-sm sm:text-base text-[var(--sg-purple)]">
                      <li>
                        <a
                          href="{serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}/{forkedProjectPath}/-/settings/ci_cd"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="inline-flex items-center font-medium text-[var(--sg-purple)] underline hover:opacity-80 break-words"
                        >
                          <span>Open your project CI/CD settings</span>
                          <Icon icon="mdi:open-in-new" class="ml-1 flex-shrink-0" width="16" />
                        </a>
                      </li>
                      <li>Expand the <strong>Variables</strong> section</li>
                      <li>Find <strong>"Minimum role to use pipeline variables"</strong></li>
                      <li>Select <strong>Developer</strong> from the dropdown</li>
                      <li>Click <strong>Save changes</strong></li>
                    </ol>
                  </div>

                  <div class="bg-[var(--sg-warning-bg)] rounded p-3 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:shield-lock" class="text-[var(--sg-warning)] mr-2 mt-0.5" width="16" />
                      <div class="text-sm text-[var(--sg-warning)]">
                        <strong>Why this is needed:</strong> This setting allows Terrateam to run pipelines with variables that contain your cloud credentials and Terraform configuration.
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markGitLabDemoStepComplete('configure-variables')}
                      class="bg-[var(--sg-purple)] hover:opacity-90 text-white px-4 py-2 rounded-lg text-sm font-medium flex items-center"
                    >
                      <Icon icon="mdi:check" class="mr-2" width="16" />
                      Variables Configured
                    </button>
                    <button
                      on:click={() => goToGitLabDemoStep('configure-webhook')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabDemoStep === 'make-changes'}
            <div class="bg-[var(--sg-purple-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-purple)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:file-edit" class="text-white" width="20" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)] mb-3 text-center sm:text-left">Make Your First Change</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-purple)] mb-6 text-center sm:text-left">
                    Now let's make a change to see Terrateam in action! We'll edit a file and create a merge request in your
                    <a
                      href="{serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}/{forkedProjectPath}"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="font-medium text-[var(--sg-purple)] underline hover:opacity-80"
                    >
                      forked repository
                    </a>.
                  </p>

                  <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-purple)]">
                    <div class="space-y-3 text-sm">
                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-1-circle" class="text-[var(--sg-purple)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">
                            Edit
                            <a
                              href="{serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}/{forkedProjectPath}/-/edit/main/dev/main.tf"
                              target="_blank"
                              rel="noopener noreferrer"
                              class="inline-flex items-center font-mono bg-[var(--sg-purple-bg)] px-2 py-0.5 rounded text-[var(--sg-purple)] underline hover:opacity-80 transition-colors"
                            >
                              dev/main.tf
                              <Icon icon="mdi:open-in-new" class="ml-1" width="14" />
                            </a>
                          </div>
                          <div class="text-[var(--sg-text-dim)] text-xs">Change <code>null_resource_count = 0</code> to <code>null_resource_count = 1</code></div>
                        </div>
                      </div>
                      <div class="flex items-center">
                        <Icon icon="mdi:numeric-2-circle" class="text-[var(--sg-purple)] mr-2" width="16" />
                        <span class="text-[var(--sg-text-muted)]">Create a new branch and push your changes</span>
                      </div>
                      <div class="flex items-center">
                        <Icon icon="mdi:numeric-3-circle" class="text-[var(--sg-purple)] mr-2" width="16" />
                        <span class="text-[var(--sg-text-muted)]">Open a merge request</span>
                      </div>
                      <div class="flex items-center">
                        <Icon icon="mdi:numeric-4-circle" class="text-[var(--sg-purple)] mr-2" width="16" />
                        <span class="text-[var(--sg-text-muted)]">Watch Terrateam automatically comment with the plan!</span>
                      </div>
                    </div>
                  </div>

                  <div class="bg-[var(--sg-accent-bg)] rounded p-3 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:lightbulb" class="text-[var(--sg-accent)] mr-2 mt-0.5" width="16" />
                      <div class="text-sm text-[var(--sg-accent)]">
                        <strong>Pro tip:</strong> When you're ready to apply the changes, comment <code class="bg-[var(--sg-accent-bg)] px-1 rounded">terrateam apply</code> on your MR.
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markGitLabDemoStepComplete('make-changes')}
                      class="bg-[var(--sg-purple)] hover:opacity-90 text-white px-4 py-2 rounded-lg text-sm font-medium"
                    >
                      I've created an MR
                    </button>
                    <button
                      on:click={() => goToGitLabDemoStep('configure-variables')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabDemoStep === 'success'}
            <div class="text-center py-12">
              <div class="inline-flex items-center justify-center w-16 h-16 bg-[var(--sg-success-bg)] rounded-full mb-6">
                <Icon icon="mdi:check-circle" class="text-[var(--sg-success)]" width="32" />
              </div>

              <h3 class="text-2xl font-semibold text-[var(--sg-text)] mb-4 flex items-center justify-center">
                <Icon icon="mdi:party-popper" class="mr-2 text-[var(--sg-success)]" width="28" />
                GitLab Demo Complete!
              </h3>

              <p class="text-[var(--sg-text-dim)] mb-6">
                You've successfully set up the Terrateam demo and seen how Terraform automation works with GitLab merge requests.
              </p>

              <div class="bg-[var(--sg-success-bg)] rounded-lg p-6 mb-6 max-w-md mx-auto">
                <h4 class="font-semibold text-[var(--sg-success)] mb-3">What you've learned:</h4>
                <div class="space-y-2 text-sm text-[var(--sg-success)]">
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    How to set up Terrateam with GitLab
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    Automatic plans on merge requests
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    GitLab CI/CD integration
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    Bot-managed Terraform workflows
                  </div>
                </div>
              </div>

              <div class="flex justify-center space-x-4">
                <button
                  on:click={() => {selectedPath = null; currentStep = 'path-selection'; currentGitLabDemoStep = 'fork';}}
                  class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-6 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                >
                  Start Over
                </button>
                <button
                  on:click={() => selectPath('repo')}
                  class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-6 py-2 rounded-lg text-sm font-medium"
                >
                  Set Up My Project
                </button>
              </div>
            </div>
          {/if}
        </div>

      {:else if currentStep === 'github-repo-setup'}
        <!-- Repository Setup Wizard -->
        <div class="mb-6">
          <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
            <h2 class="text-lg sm:text-xl font-semibold text-[var(--sg-text)]">Repository Setup</h2>
            <button
              on:click={goBack}
              class="text-xs md:text-sm text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] flex items-center self-start sm:self-auto"
            >
              <Icon icon="mdi:arrow-left" class="mr-1" width="16" />
              Back
            </button>
          </div>

          <!-- Repository Steps Progress -->
          <div class="mb-8">
            <div class="flex items-center justify-between mb-4">
              {#each [
                {step: 'install-app', index: 0, label: '1'},
                {step: 'select-repo', index: 1, label: '2'},
                {step: 'add-workflow', index: 2, label: '3'},
                {step: 'configure', index: 3, label: '4'},
                {step: 'test', index: 4, label: '5'},
                {step: 'success', index: 5, label: '6'}
              ] as stepInfo}
                <div class="flex items-center {stepInfo.index < 5 ? 'flex-1' : ''}">
                  <div class="flex items-center justify-center w-8 h-8 sm:w-10 sm:h-10 rounded-full text-xs sm:text-sm font-medium
                              {currentRepoStep === stepInfo.step ? 'bg-[var(--sg-accent-button)] text-white' :
                               (stepInfo.step === 'install-app' && repoStepCompleted['install-app']) ||
                               (stepInfo.step === 'select-repo' && repoStepCompleted['select-repo']) ||
                               (stepInfo.step === 'add-workflow' && repoStepCompleted['add-workflow']) ||
                               (stepInfo.step === 'configure' && repoStepCompleted.configure) ||
                               (stepInfo.step === 'test' && repoStepCompleted.test)
                               ? 'bg-[var(--sg-success)] text-white' :
                               'bg-[var(--sg-bg-2)] text-[var(--sg-text-dim)]'}">
                    {#if (stepInfo.step === 'install-app' && repoStepCompleted['install-app']) ||
                         (stepInfo.step === 'select-repo' && repoStepCompleted['select-repo']) ||
                         (stepInfo.step === 'add-workflow' && repoStepCompleted['add-workflow']) ||
                         (stepInfo.step === 'configure' && repoStepCompleted.configure) ||
                         (stepInfo.step === 'test' && repoStepCompleted.test)}
                      <Icon icon="mdi:check" class="text-white" width="16" />
                    {:else}
                      {stepInfo.label}
                    {/if}
                  </div>
                  {#if stepInfo.index < 5}
                    <div class="flex-1 h-1 mx-2 {
                      (stepInfo.step === 'install-app' && repoStepCompleted['install-app']) ||
                      (stepInfo.step === 'select-repo' && repoStepCompleted['select-repo']) ||
                      (stepInfo.step === 'add-workflow' && repoStepCompleted['add-workflow']) ||
                      (stepInfo.step === 'configure' && repoStepCompleted.configure) ||
                      (stepInfo.step === 'test' && repoStepCompleted.test)
                      ? 'bg-[var(--sg-success)]' : 'bg-[var(--sg-bg-2)]'}"></div>
                  {/if}
                </div>
              {/each}
            </div>
            <div class="text-center text-xs sm:text-sm text-[var(--sg-text-dim)]">
              Step {['install-app', 'select-repo', 'add-workflow', 'configure', 'test', 'success'].indexOf(currentRepoStep) + 1} of 6
            </div>
          </div>

          <!-- Repository Step Content -->
          {#if currentRepoStep === 'install-app'}
            <div class="bg-[var(--sg-success-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-success)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:download" class="text-white" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-success)] mb-2 text-center sm:text-left">Step 1: Install Terrateam GitHub App</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-success)] mb-4 text-center sm:text-left">
                    Install the Terrateam GitHub App on your organization to enable Terraform automation.
                  </p>

                  {#if hasInstallations}
                    <div class="bg-[var(--sg-success-bg)] rounded-lg p-3 sm:p-4 mb-4 border border-[var(--sg-success)]">
                      <div class="flex items-start sm:items-center">
                        <Icon icon="mdi:check-circle" class="text-[var(--sg-success)] mr-2 flex-shrink-0 mt-0.5 sm:mt-0" width="20" />
                        <span class="text-xs sm:text-sm text-[var(--sg-success)] font-medium">
                          Great! We detected {installations.length} GitHub installation{installations.length > 1 ? 's' : ''}.
                        </span>
                      </div>
                    </div>
                  {:else}
                    <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-success)]">
                      <div class="flex items-center justify-between">
                        <div>
                          <div class="font-medium text-[var(--sg-text)]">Terrateam GitHub App</div>
                          <div class="text-sm text-[var(--sg-text-dim)]">Enables Terraform automation in your repositories</div>
                        </div>
                        <Icon icon="mdi:github" class="text-[var(--sg-text-dim)]" width="24" />
                      </div>
                    </div>
                  {/if}

                  <div class="bg-[var(--sg-accent-bg)] rounded-lg p-3 sm:p-4 mb-4 border border-[var(--sg-accent)]">
                    <div class="flex items-start">
                      <Icon icon="mdi:information" class="text-[var(--sg-accent)] mr-2 mt-0.5 flex-shrink-0" width="20" />
                      <div class="text-xs sm:text-sm text-[var(--sg-accent)]">
                        <p class="font-medium mb-1">Repository in a different organization?</p>
                        <p>You can install the app on any organization where your repository is located.</p>
                      </div>
                    </div>
                  </div>

                  <div class="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
                    <button
                      on:click={() => openExternalLink(githubAppUrl, 'github_app_install')}
                      class="bg-[var(--sg-success)] hover:bg-[var(--sg-success)] text-white px-4 py-2.5 rounded-lg text-sm font-medium flex items-center justify-center"
                    >
                      <Icon icon="mdi:download" class="mr-2" width="16" />
                      Install GitHub App
                    </button>
                    <button
                      on:click={checkRepoAppInstallation}
                      disabled={checkingAppInstallation}
                      class="border border-[var(--sg-success)] text-[var(--sg-success)] px-4 py-2.5 rounded-lg text-sm font-medium hover:bg-[var(--sg-success-bg)] disabled:opacity-50 flex items-center justify-center"
                    >
                      {#if checkingAppInstallation}
                        <Icon icon="mdi:loading" class="animate-spin mr-2" width="16" />
                        Checking...
                      {:else if hasInstallations}
                        Continue
                      {:else}
                        Check Installation
                      {/if}
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentRepoStep === 'select-repo'}
            <div class="bg-[var(--sg-accent-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-accent-button)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:source-repository" class="text-white" width="20" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-accent)] mb-2">Step 2: Select Repository</h3>
                  <p class="text-[var(--sg-accent)] mb-4">
                    Choose the repository where you want to enable Terrateam automation.
                  </p>

                  {#if installations.length > 1}
                    <div class="mb-4">
                      <label for="organization-select" class="block text-sm font-medium text-[var(--sg-accent)] mb-2">{VCS_PROVIDERS[currentProvider].displayName} {terminology.organization}:</label>
                      <select
                        id="organization-select"
                        bind:value={selectedInstallationId}
                        on:change={() => {
                          selectedInstallation = installations.find(i => i.id === selectedInstallationId) || null;
                        }}
                        class="w-full p-2 border border-[var(--sg-accent)] rounded-lg bg-[var(--sg-bg-1)] text-[var(--sg-text)]"
                      >
                        <option value="">Select a {terminology.organization}...</option>
                        {#each installations as installation}
                          <option value={installation.id}>{installation.name}</option>
                        {/each}
                      </select>
                    </div>
                  {:else if installations.length === 1}
                    {#if !selectedInstallation}
                      {selectedInstallation = installations[0]}
                      {selectedInstallationId = installations[0].id}
                    {/if}
                    <div class="bg-[var(--sg-accent-bg)] rounded-lg p-3 mb-4 border border-[var(--sg-accent)]">
                      <div class="flex items-center">
                        <Icon icon="mdi:github" class="text-[var(--sg-accent)] mr-2" width="16" />
                        <span class="text-[var(--sg-accent)] font-medium">{installations[0].name}</span>
                      </div>
                    </div>
                  {/if}

                  {#if selectedInstallation}
                    <div class="mb-4">
                      <div class="flex items-center justify-between mb-2">
                        <span class="block text-sm font-medium text-[var(--sg-accent)]">Choose Repository:</span>
                        <button
                          on:click={refreshRepositories}
                          disabled={isLoadingRepos}
                          class="text-xs text-[var(--sg-accent)] hover:underline disabled:opacity-50"
                        >
                          {isLoadingRepos ? 'Refreshing...' : 'Refresh'}
                        </button>
                      </div>

                      <div class="bg-[var(--sg-accent-bg)] rounded-lg p-3 mb-3 border border-[var(--sg-accent)]">
                        <div class="flex items-start">
                          <Icon icon="mdi:information" class="text-[var(--sg-accent)] mr-2 mt-0.5" width="16" />
                          <div class="text-sm text-[var(--sg-accent)]">
                            <p class="font-medium mb-1">Repository Access</p>
                            <p>Only repositories where the GitHub app is installed and enabled will appear here. If you don't see your repository, you may need to <button on:click={() => openExternalLink(githubAppUrl)} class="font-medium text-[var(--sg-accent)] underline hover:text-[var(--sg-accent-hover)]">configure app access</button> first.</p>
                          </div>
                        </div>
                      </div>

                      {#if isLoadingRepos}
                        <div class="flex items-center justify-center p-8">
                          <LoadingSpinner size="md" centered={false} />
                        </div>
                      {:else if repoLoadError}
                        <div class="bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-lg p-4">
                          <p class="text-[var(--sg-error)] text-sm">{repoLoadError}</p>
                        </div>
                      {:else if repositories.length === 0}
                        <div class="bg-[var(--sg-warning-bg)] border border-[var(--sg-warning)] rounded-lg p-4">
                          <div class="flex items-start">
                            <Icon icon="mdi:alert" class="text-[var(--sg-warning)] mr-3 mt-0.5" width="20" />
                            <div class="flex-1">
                              <p class="text-[var(--sg-warning)] text-sm font-medium mb-2">No repositories found</p>
                              <p class="text-[var(--sg-warning)] text-sm mb-3">
                                The GitHub App doesn't have access to any repositories in this organization. You may need to configure repository access.
                              </p>
                              <button
                                on:click={() => openExternalLink(githubAppUrl, 'github_app_install')}
                                class="bg-[var(--sg-warning)] hover:bg-[var(--sg-warning)] text-white px-3 py-2 rounded text-sm font-medium flex items-center"
                              >
                                <Icon icon="mdi:cog" class="mr-2" width="16" />
                                Configure App Access
                              </button>
                            </div>
                          </div>
                        </div>
                      {:else}
                        <div class="max-h-60 overflow-y-auto border border-[var(--sg-accent)] rounded-lg">
                          {#each repositories as repo}
                            <button
                              on:click={() => selectRepository(repo)}
                              class="w-full text-left p-3 border-b border-[var(--sg-accent)] last:border-b-0 hover:bg-[var(--sg-accent-bg)] {selectedRepository?.id === repo.id ? 'bg-[var(--sg-accent-bg)]' : ''}"
                            >
                              <div class="flex items-center justify-between">
                                <div>
                                  <div class="font-medium text-[var(--sg-text)]">{repo.name}</div>
                                  <div class="text-sm text-[var(--sg-text-dim)]">Repository setup: {repo.setup ? 'Complete' : 'Pending'}</div>
                                </div>
                                {#if selectedRepository?.id === repo.id}
                                  <Icon icon="mdi:check-circle" class="text-[var(--sg-accent)]" width="20" />
                                {/if}
                              </div>
                            </button>
                          {/each}
                        </div>
                      {/if}
                    </div>
                  {/if}

                  <div class="flex items-center space-x-3">
                    {#if selectedRepository}
                      <button
                        on:click={() => markRepoStepComplete('select-repo')}
                        class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                      >
                        Continue with {selectedRepository.name}
                      </button>
                    {/if}
                    <button
                      on:click={() => goToRepoStep('install-app')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentRepoStep === 'add-workflow'}
            <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-warning)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:file-plus" class="text-white" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-lg sm:text-xl font-semibold text-[var(--sg-warning)] mb-3 text-center sm:text-left">Step 3: Add GitHub Actions Workflow</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-warning)] mb-6 text-center sm:text-left">
                    Add the Terrateam workflow file to your repository's default branch to enable automation.
                  </p>

                  <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 sm:p-5 mb-4 border border-[var(--sg-warning)]">
                    <div class="space-y-6">
                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-warning)] rounded-full flex items-center justify-center text-white text-sm font-bold">1</div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base mb-2 text-center sm:text-left">Create a new branch in <strong class="break-all">{selectedRepository?.name}</strong></div>
                          <div class="bg-[var(--sg-bg-2)] p-3 rounded overflow-x-auto">
                            <code class="text-xs sm:text-sm font-mono whitespace-nowrap">git checkout -b add-terrateam-workflow</code>
                          </div>
                        </div>
                      </div>

                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-warning)] rounded-full flex items-center justify-center text-white text-sm font-bold">2</div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base mb-2 text-center sm:text-left">Create the workflow directory and file</div>
                          <div class="bg-[var(--sg-bg-2)] p-3 rounded overflow-x-auto text-xs sm:text-sm">
                            <code class="font-mono">
                              <span class="block">mkdir -p .github/workflows</span>
                              <span class="block mt-2">curl -o .github/workflows/terrateam.yml \</span>
                              <span class="block ml-2 sm:ml-4 break-all">https://raw.githubusercontent.com/terrateamio/terrateam-example/refs/heads/main/github/actions/workflows/default/terrateam.yml</span>
                            </code>
                          </div>
                        </div>
                      </div>

                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-warning)] rounded-full flex items-center justify-center text-white text-sm font-bold">3</div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base mb-2 text-center sm:text-left">Commit and push the workflow</div>
                          <div class="bg-[var(--sg-bg-2)] p-3 rounded overflow-x-auto text-xs sm:text-sm">
                            <code class="font-mono">
                              <span class="block">git add .github/workflows/terrateam.yml</span>
                              <span class="block mt-2">git commit -m "Add Terrateam workflow"</span>
                              <span class="block mt-2">git push -u origin add-terrateam-workflow</span>
                            </code>
                          </div>
                        </div>
                      </div>

                      <div class="flex flex-col sm:flex-row sm:items-start gap-3">
                        <div class="flex-shrink-0 flex justify-center sm:block">
                          <div class="w-8 h-8 bg-[var(--sg-warning)] rounded-full flex items-center justify-center text-white text-sm font-bold">4</div>
                        </div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm sm:text-base text-center sm:text-left">Create a pull request and merge it to your default branch</div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="bg-[var(--sg-accent-bg)] rounded p-3 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:information" class="text-[var(--sg-accent)] mr-2 mt-0.5" width="16" />
                      <div class="text-sm text-[var(--sg-accent)]">
                        <strong>Important:</strong> The workflow file must be in your default branch (usually <code>main</code> or <code>master</code>) to be active.
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markRepoStepComplete('add-workflow')}
                      class="bg-[var(--sg-warning)] hover:bg-[var(--sg-warning)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                    >
                      Workflow Added
                    </button>
                    <button
                      on:click={() => goToRepoStep('select-repo')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentRepoStep === 'configure'}
            <div class="bg-[var(--sg-purple-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-purple)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:cog" class="text-white" width="20" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-text)] mb-2 text-center sm:text-left">Step 4: Configure Cloud Credentials</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-purple)] mb-4 text-center sm:text-left">
                    Set up cloud provider credentials so Terrateam can manage your infrastructure.
                  </p>

                  <div class="bg-[var(--sg-purple-bg)] rounded-lg p-3 sm:p-4 mb-4 border border-[var(--sg-purple)]">
                    <div class="space-y-4">
                      <div class="flex items-start">
                        <div class="flex-shrink-0 w-7 h-7 bg-[var(--sg-purple)] rounded-full flex items-center justify-center text-white text-xs font-bold mr-3 mt-0.5">1</div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm mb-1">Go to your repository settings</div>
                          <div class="text-[var(--sg-text-dim)] text-xs">Settings → Secrets and variables → Actions</div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <div class="flex-shrink-0 w-7 h-7 bg-[var(--sg-purple)] rounded-full flex items-center justify-center text-white text-xs font-bold mr-3 mt-0.5">2</div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm mb-1">Add your cloud provider credentials as repository secrets</div>
                          <div class="bg-[var(--sg-bg-2)] rounded p-2 text-xs">
                            <div class="space-y-2 font-mono">
                              <div>
                                <span class="font-bold text-[var(--sg-text-muted)]">AWS:</span>
                                <div class="ml-2 text-[var(--sg-text-dim)]">AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY</div>
                              </div>
                              <div>
                                <span class="font-bold text-[var(--sg-text-muted)]">GCP:</span>
                                <div class="ml-2 text-[var(--sg-text-dim)]">GOOGLE_CREDENTIALS (service account JSON)</div>
                              </div>
                              <div>
                                <span class="font-bold text-[var(--sg-text-muted)]">Azure:</span>
                                <div class="ml-2 text-[var(--sg-text-dim)] break-words">ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID</div>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <div class="flex-shrink-0 w-7 h-7 bg-[var(--sg-purple)] rounded-full flex items-center justify-center text-white text-xs font-bold mr-3 mt-0.5">3</div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm mb-1">Make sure your Terraform configurations are ready</div>
                          <div class="text-[var(--sg-text-dim)] text-xs">Valid .tf files with proper provider configurations</div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="bg-[var(--sg-warning-bg)] rounded-lg p-3 sm:p-4 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:shield-lock" class="text-[var(--sg-warning)] mr-2 mt-0.5 flex-shrink-0" width="18" />
                      <div class="text-xs sm:text-sm text-[var(--sg-warning)]">
                        <strong>Security tip:</strong> Consider using OIDC for enhanced security instead of static credentials. Check our cloud provider guides for OIDC setup instructions.
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markRepoStepComplete('configure')}
                      class="bg-[var(--sg-purple)] hover:opacity-90 text-white px-4 py-2 rounded-lg text-sm font-medium"
                    >
                      Credentials Configured
                    </button>
                    <button
                      on:click={() => goToRepoStep('add-workflow')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentRepoStep === 'test'}
            <div class="bg-[var(--sg-success-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-success)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:test-tube" class="text-white" width="24" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-success)] mb-2 text-center sm:text-left">Step 5: Test Your Setup</h3>
                  <p class="text-sm sm:text-base text-[var(--sg-success)] mb-4 text-center sm:text-left">
                    Let's test your Terrateam setup by making a change and creating a pull request.
                  </p>

                  <div class="bg-[var(--sg-success-bg)] rounded-lg p-3 sm:p-4 mb-4 border border-[var(--sg-success)]">
                    <div class="space-y-4">
                      <div class="flex items-start">
                        <div class="flex-shrink-0 w-7 h-7 bg-[var(--sg-success)] rounded-full flex items-center justify-center text-white text-xs font-bold mr-3 mt-0.5">1</div>
                        <div class="flex-1 min-w-0">
                          <div class="font-medium text-[var(--sg-text)] text-sm mb-1">Make a change to any <code class="bg-[var(--sg-success-bg)] px-1.5 py-0.5 rounded text-xs font-mono">.tf</code> file in your repository</div>
                          <div class="text-[var(--sg-text-dim)] text-xs">Even a small comment change will work for testing</div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <div class="flex-shrink-0 w-7 h-7 bg-[var(--sg-success)] rounded-full flex items-center justify-center text-white text-xs font-bold mr-3 mt-0.5">2</div>
                        <div class="flex-1 min-w-0">
                          <div class="font-medium text-[var(--sg-text)] text-sm mb-1">Create a new branch and commit your changes</div>
                          <div class="bg-[var(--sg-bg-2)] p-2 rounded overflow-x-auto">
                            <code class="text-xs font-mono">
                              <span class="block">git checkout -b test-terrateam</span>
                              <span class="block mt-1">git add -A</span>
                              <span class="block mt-1">git commit -m "Test Terrateam setup"</span>
                              <span class="block mt-1">git push -u origin test-terrateam</span>
                            </code>
                          </div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <div class="flex-shrink-0 w-7 h-7 bg-[var(--sg-success)] rounded-full flex items-center justify-center text-white text-xs font-bold mr-3 mt-0.5">3</div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm mb-1">Open a pull request</div>
                          <div class="text-[var(--sg-text-dim)] text-xs">Terrateam should automatically comment with the terraform plan!</div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <div class="flex-shrink-0 w-7 h-7 bg-[var(--sg-success)] rounded-full flex items-center justify-center text-white text-xs font-bold mr-3 mt-0.5">4</div>
                        <div class="flex-1">
                          <div class="font-medium text-[var(--sg-text)] text-sm">If you want to apply the changes, comment <code class="bg-[var(--sg-success-bg)] px-1.5 py-0.5 rounded text-xs font-mono">terrateam apply</code></div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="bg-[var(--sg-success-bg)] rounded p-3 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:lightbulb" class="text-[var(--sg-success)] mr-2 mt-0.5" width="16" />
                      <div class="text-sm text-[var(--sg-success)]">
                        <strong>Success indicators:</strong> Look for Terrateam's bot comment with the terraform plan output and green status checks.
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markRepoStepComplete('test')}
                      class="bg-[var(--sg-success)] hover:bg-[var(--sg-success)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                    >
                      It Works!
                    </button>
                    <button
                      on:click={() => goToRepoStep('configure')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentRepoStep === 'success'}
            <div class="text-center py-12">
              <div class="inline-flex items-center justify-center w-16 h-16 bg-[var(--sg-success-bg)] rounded-full mb-6">
                <Icon icon="mdi:check-circle" class="text-[var(--sg-success)]" width="32" />
              </div>
              <h3 class="text-2xl font-semibold text-[var(--sg-text)] mb-2 flex items-center justify-center">
                <Icon icon="mdi:party-popper" class="text-[var(--sg-purple)] mr-2" width="28" />
                Repository Setup Complete!
              </h3>
              <p class="text-[var(--sg-text-dim)] mb-6 px-4">
                Terrateam is now configured for<br class="sm:hidden">
                <strong class="text-[var(--sg-accent)] break-all">{selectedRepository?.name}</strong>.<br class="sm:hidden">
                You're ready to automate your Terraform workflows!
              </p>

              <div class="bg-[var(--sg-success-bg)] rounded-lg p-6 mb-6 max-w-md mx-auto">
                <h4 class="font-semibold text-[var(--sg-success)] mb-3">What you've set up:</h4>
                <div class="space-y-2 text-sm text-[var(--sg-success)]">
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                    GitHub App installed and configured
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                    Terrateam workflow active in your repository
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                    Cloud credentials securely configured
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2" width="16" />
                    Automated Terraform plans on pull requests
                  </div>
                </div>
              </div>

              <div class="bg-[var(--sg-accent-bg)] rounded-lg p-6 mb-6 max-w-md mx-auto">
                <h4 class="font-semibold text-[var(--sg-accent)] mb-3 flex items-center">
                  <Icon icon="mdi:rocket-launch" class="text-[var(--sg-accent)] mr-2" width="20" />
                  Ready for Advanced Configuration?
                </h4>
                <p class="text-sm text-[var(--sg-accent)] mb-4">
                  Take your Terrateam setup to the next level with our Configuration Wizard.
                  Generate custom workflows, set up advanced features, and optimize for your specific use case.
                </p>
                <button
                  on:click={openConfigurationWizard}
                  class="w-full bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-4 py-3 rounded-lg text-sm font-medium flex items-center justify-center"
                >
                  <Icon icon="mdi:auto-fix" class="mr-2" width="20" />
                  Open Configuration Wizard
                </button>
              </div>

              <div class="flex flex-col sm:flex-row justify-center gap-3 sm:gap-4">
                <button
                  on:click={() => window.location.hash = '#/repositories'}
                  class="bg-[var(--sg-bg-2)] hover:bg-[var(--sg-bg-2)] text-white px-6 py-3 rounded-lg text-sm font-medium w-full sm:w-auto"
                >
                  View My Repositories
                </button>
                <button
                  on:click={() => openExternalLink('https://docs.terrateam.io/')}
                  class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-6 py-3 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)] w-full sm:w-auto"
                >
                  Read Documentation
                </button>
              </div>
            </div>
          {/if}
        </div>

      {:else if currentStep === 'gitlab-setup'}
        <!-- GitLab Setup Wizard -->
        <div class="mb-6">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-lg md:text-xl font-semibold text-[var(--sg-text)]">GitLab Setup</h2>
            <button
              on:click={goBack}
              class="text-xs md:text-sm text-[var(--sg-text-dim)] hover:text-[var(--sg-text-muted)] flex items-center"
            >
              <Icon icon="mdi:arrow-left" class="mr-1" width="16" />
              Back
            </button>
          </div>

          <!-- GitLab Steps Progress -->
          <div class="mb-8">
            <div class="grid grid-cols-7 gap-1 mb-4 px-1">
              {#each [
                {step: 'select-group', index: 0, label: '1'},
                {step: 'select-repo', index: 1, label: '2'},
                {step: 'submit-token', index: 2, label: '3'},
                {step: 'configure-webhook', index: 3, label: '4'},
                {step: 'configure-variables', index: 4, label: '5'},
                {step: 'add-pipeline', index: 5, label: '6'},
                {step: 'success', index: 6, label: '7'}
              ] as stepInfo}
                <div class="flex justify-center">
                  <div class="flex items-center justify-center w-8 h-8 rounded-full text-xs font-medium
                              {currentGitLabStep === stepInfo.step ? 'bg-[var(--sg-accent-button)] text-white' :
                               (stepInfo.step === 'select-group' && gitlabStepCompleted['select-group']) ||
                               (stepInfo.step === 'select-repo' && gitlabStepCompleted['select-repo']) ||
                               (stepInfo.step === 'submit-token' && gitlabStepCompleted['submit-token']) ||
                               (stepInfo.step === 'configure-webhook' && gitlabStepCompleted['configure-webhook']) ||
                               (stepInfo.step === 'configure-variables' && gitlabStepCompleted['configure-variables']) ||
                               (stepInfo.step === 'add-pipeline' && gitlabStepCompleted['add-pipeline'])
                               ? 'bg-[var(--sg-success)] text-white' :
                               'bg-[var(--sg-bg-2)] text-[var(--sg-text-dim)]'}">
                    {#if (stepInfo.step === 'select-group' && gitlabStepCompleted['select-group']) ||
                         (stepInfo.step === 'select-repo' && gitlabStepCompleted['select-repo']) ||
                         (stepInfo.step === 'submit-token' && gitlabStepCompleted['submit-token']) ||
                         (stepInfo.step === 'configure-webhook' && gitlabStepCompleted['configure-webhook']) ||
                         (stepInfo.step === 'configure-variables' && gitlabStepCompleted['configure-variables']) ||
                         (stepInfo.step === 'add-pipeline' && gitlabStepCompleted['add-pipeline'])}
                      <Icon icon="mdi:check" class="text-white" width="16" />
                    {:else}
                      {stepInfo.label}
                    {/if}
                  </div>
                </div>
              {/each}
            </div>
            <div class="text-center text-xs sm:text-sm text-[var(--sg-text-dim)]">
              Step {['select-group', 'select-repo', 'submit-token', 'configure-webhook', 'configure-variables', 'add-pipeline', 'success'].indexOf(currentGitLabStep) + 1} of 7
            </div>
          </div>

          <!-- GitLab Step Content -->
          {#if currentGitLabStep === 'select-group'}
            <div class="bg-[var(--sg-accent-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-accent-button)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:account-group" class="text-white" width="20" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-accent)] mb-2">Select GitLab Group</h3>
                  <p class="text-[var(--sg-accent)] mb-4">
                    Choose the GitLab group where you want to connect your repository.
                  </p>

                  {#if isLoadingGitLabSetupGroups}
                    <div class="flex items-center justify-center p-8">
                      <LoadingSpinner size="md" centered={false} />
                    </div>
                  {:else if gitlabSetupGroupsError}
                    <div class="bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-lg p-4 mb-4">
                      <p class="text-[var(--sg-error)] text-sm">{gitlabSetupGroupsError}</p>
                    </div>
                    <div class="flex items-center space-x-3">
                      <button
                        on:click={loadGitLabSetupGroups}
                        class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                      >
                        Retry
                      </button>
                    </div>
                  {:else if gitlabGroups.length === 0}
                    <div class="bg-[var(--sg-warning-bg)] border border-[var(--sg-warning)] rounded-lg p-4 mb-4">
                      <p class="text-[var(--sg-warning)] text-sm">
                        No GitLab groups found. You need to be a member of a GitLab group to connect repositories.
                      </p>
                    </div>
                  {:else}
                    <div class="max-h-60 overflow-y-auto border border-[var(--sg-accent)] rounded-lg mb-4">
                      {#each gitlabGroups as group}
                        <button
                          on:click={() => selectGitLabGroup(group)}
                          class="w-full text-left p-3 border-b border-[var(--sg-accent)] last:border-b-0 hover:bg-[var(--sg-accent-bg)] {selectedGitLabGroup?.id === group.id ? 'bg-[var(--sg-accent-bg)]' : ''}"
                        >
                          <div class="flex items-center justify-between">
                            <div>
                              <div class="font-medium text-[var(--sg-text)]">{group.name}</div>
                            </div>
                            {#if selectedGitLabGroup?.id === group.id}
                              <Icon icon="mdi:check-circle" class="text-[var(--sg-accent)]" width="20" />
                            {/if}
                          </div>
                        </button>
                      {/each}
                    </div>

                    {#if selectedGitLabGroup}
                      <div class="flex items-center space-x-3">
                        <button
                          on:click={() => markGitLabStepComplete('select-group')}
                          class="bg-[var(--sg-accent-button)] hover:bg-[var(--sg-accent-button-hover)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                        >
                          Continue with {selectedGitLabGroup.name}
                        </button>
                      </div>
                    {/if}
                  {/if}
                </div>
              </div>
            </div>

          {:else if currentGitLabStep === 'select-repo'}
            <div class="bg-[var(--sg-success-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-success)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:source-repository" class="text-white" width="20" />
                  </div>
                </div>
                <div class="flex-1">
                  <h3 class="text-base sm:text-lg font-semibold text-[var(--sg-success)] mb-2">Select Repository</h3>
                  <p class="text-[var(--sg-success)] mb-4">
                    Choose the repository where you want to enable Terrateam automation.
                  </p>

                  {#if selectedGitLabGroup}
                    <div class="bg-[var(--sg-success-bg)] rounded-lg p-3 mb-4 border border-[var(--sg-success)]">
                      <div class="flex items-center">
                        <Icon icon="mdi:account-group" class="text-[var(--sg-success)] mr-2" width="16" />
                        <span class="text-[var(--sg-success)] font-medium">{selectedGitLabGroup.name}</span>
                      </div>
                    </div>

                    <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-success)]">
                      <h4 class="text-sm font-medium text-[var(--sg-text)] mb-3">Add Repository</h4>
                      <div class="space-y-3">
                        <div>
                          <label for="gitlab-project-name" class="block text-sm text-[var(--sg-text-muted)] mb-1">
                            Enter your repository name
                          </label>
                          <div class="flex flex-col gap-3">
                            <div class="flex items-center min-w-0">
                              <span class="px-2 sm:px-3 py-2 bg-[var(--sg-bg-2)] border border-r-0 border-[var(--sg-border)] rounded-l-lg text-[var(--sg-text-dim)] text-xs sm:text-sm whitespace-nowrap flex-shrink-0">
                                {selectedGitLabGroup?.name}/
                              </span>
                              <input
                                id="gitlab-project-name"
                                type="text"
                                bind:value={manualGitLabProject}
                                placeholder="my-terraform-repo"
                                class="flex-1 min-w-0 px-2 sm:px-3 py-2 border border-[var(--sg-border)] rounded-r-lg bg-[var(--sg-bg-1)] text-[var(--sg-text)] placeholder-[var(--sg-text-dim)] focus:outline-none focus:ring-2 focus:ring-[var(--sg-success)] focus:border-transparent text-xs sm:text-sm"
                                on:keypress={(e) => {
                                  if (e.key === 'Enter' && manualGitLabProject.trim()) {
                                    addGitLabProject();
                                  }
                                }}
                              />
                            </div>
                            <button
                              on:click={addGitLabProject}
                              disabled={!manualGitLabProject.trim() || isAddingGitLabProject}
                              class="w-full px-4 py-2 bg-[var(--sg-success)] text-white rounded-lg hover:bg-[var(--sg-success)] disabled:bg-[var(--sg-bg-2)] disabled:cursor-not-allowed text-sm font-medium"
                            >
                              {isAddingGitLabProject ? 'Adding...' : 'Continue'}
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  {/if}


                  <div class="flex items-center space-x-3 mt-4">
                    <button
                      on:click={() => goToGitLabStep('select-group')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabStep === 'submit-token'}
            <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-warning)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:key" class="text-white" width="20" />
                  </div>
                </div>
                <div class="ml-4 flex-1">
                  <h3 class="text-lg font-semibold text-[var(--sg-warning)] mb-2">Submit GitLab Access Token</h3>
                  <p class="text-[var(--sg-warning)] mb-4">
                    Terrateam uses this token to call the GitLab API on behalf of your group. Choose the most narrowly-scoped token that fits your setup.
                  </p>

                  <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-warning)]">
                    <GitLabTokenInstructions
                      webBaseUrl={serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}
                      groupName={selectedGitLabGroup?.name || null}
                      projectPath={selectedGitLabGroup && manualGitLabProject ? `${selectedGitLabGroup.name}/${manualGitLabProject}` : null}
                    />
                  </div>

                  <div class="mb-4">
                    <label for="gitlab-access-token" class="block text-sm font-medium text-[var(--sg-text-muted)] mb-2">
                      Access Token
                    </label>
                    <input
                      id="gitlab-access-token"
                      type="password"
                      bind:value={gitlabAccessToken}
                      placeholder="Enter your GitLab access token"
                      class="w-full px-4 py-2 border border-[var(--sg-border)] rounded-lg
                             bg-[var(--sg-bg-1)] text-[var(--sg-text)]
                             focus:ring-2 focus:ring-[var(--sg-warning)] focus:border-[var(--sg-warning)]
                             disabled:opacity-50 disabled:cursor-not-allowed"
                      disabled={isSubmittingGitLabToken || gitlabTokenSubmitted}
                    />
                  </div>

                  {#if gitlabTokenError}
                    <div class="bg-[var(--sg-error-bg)] rounded p-3 mb-4">
                      <div class="flex items-start">
                        <Icon icon="mdi:alert-circle" class="text-[var(--sg-error)] mr-2 mt-0.5" width="16" />
                        <div class="text-sm text-[var(--sg-error)]">{gitlabTokenError}</div>
                      </div>
                    </div>
                  {/if}

                  {#if gitlabTokenSubmitted}
                    <div class="bg-[var(--sg-success-bg)] rounded p-3 mb-4">
                      <div class="flex items-start">
                        <Icon icon="mdi:check-circle" class="text-[var(--sg-success)] mr-2 mt-0.5" width="16" />
                        <div class="text-sm text-[var(--sg-success)]">
                          <strong>Success!</strong> Access token submitted successfully.
                        </div>
                      </div>
                    </div>
                  {/if}

                  <div class="flex items-center justify-end space-x-3">
                    <button
                      on:click={() => goToGitLabStep('select-repo')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                    <button
                      on:click={submitGitLabAccessToken}
                      disabled={isSubmittingGitLabToken || gitlabTokenSubmitted || !gitlabAccessToken.trim()}
                      class="bg-[var(--sg-warning)] hover:bg-[var(--sg-warning)] text-white px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed flex items-center"
                    >
                      {#if isSubmittingGitLabToken}
                        <LoadingSpinner size="sm" color="white" centered={false} />
                        <span class="ml-2">Submitting...</span>
                      {:else if gitlabTokenSubmitted}
                        <Icon icon="mdi:check" class="mr-2" width="16" />
                        Submitted
                      {:else}
                        Submit Token
                      {/if}
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabStep === 'configure-webhook'}
            <div class="bg-[var(--sg-warning-bg)] rounded-lg p-6">
              <div class="flex items-start">
                <div class="flex-shrink-0">
                  <div class="flex items-center justify-center w-10 h-10 bg-[var(--sg-warning-bg)] rounded-lg">
                    <Icon icon="mdi:webhook" class="text-[var(--sg-warning)]" width="20" />
                  </div>
                </div>
                <div class="ml-4 flex-1">
                  <h3 class="text-base md:text-lg font-medium text-[var(--sg-warning)] mb-2">
                    Configure Webhook
                  </h3>
                  <p class="text-[var(--sg-warning)] mb-4">
                    Add a webhook to your project so Terrateam can respond to merge requests and code changes.
                  </p>

                  <div class="bg-[var(--sg-warning-bg)] rounded-lg p-4 mb-4">
                    <h4 class="font-medium text-[var(--sg-warning)] mb-2">Instructions:</h4>
                    <ol class="list-decimal list-inside space-y-2 text-sm text-[var(--sg-warning)]">
                      <li>
                        <a
                          href="{serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}/{selectedGitLabGroup?.name || ''}/{manualGitLabProject || ''}/-/hooks"
                          target="_blank"
                          rel="noopener noreferrer"
                          class="inline-flex items-center font-medium text-[var(--sg-warning)] underline hover:text-[var(--sg-warning)]"
                        >
                          Open your project webhooks
                          <Icon icon="mdi:open-in-new" class="ml-1" width="16" />
                        </a>
                      </li>
                      <li>Click <strong>Add new webhook</strong></li>
                      <li>URL: <code class="bg-[var(--sg-warning-bg)] px-1 rounded break-all">{webhookUrl || 'Loading...'}</code></li>
                      <li>Secret token: <code class="bg-[var(--sg-warning-bg)] px-1 rounded break-all">{webhookSecret || 'Loading...'}</code></li>
                      <li>Enable these triggers:
                        <ul class="list-disc list-inside ml-4 mt-1">
                          <li>Push events</li>
                          <li>Comments</li>
                          <li>Merge request events</li>
                        </ul>
                      </li>
                      <li>Click <strong>Add webhook</strong></li>
                      <li>Find the new Terrateam webhook in the list and click <strong>Test</strong> → <strong>Push events</strong> to activate it</li>
                      <li>Click <strong>Verify Webhook</strong> below</li>
                    </ol>
                  </div>

                  {#if webhookVerificationError}
                    <div class="bg-[var(--sg-error-bg)] border border-[var(--sg-error)] rounded-lg p-4 mb-4">
                      <div class="flex items-start">
                        <Icon icon="mdi:alert-circle" class="text-[var(--sg-error)] mr-2 mt-0.5" width="20" />
                        <p class="text-sm text-[var(--sg-error)]">{webhookVerificationError}</p>
                      </div>
                    </div>
                  {/if}

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={verifyWebhook}
                      disabled={checkingWebhook}
                      class="bg-[var(--sg-warning)] hover:bg-[var(--sg-warning)] text-white px-4 py-2 rounded-lg text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed flex items-center"
                    >
                      {#if checkingWebhook}
                        <svg class="w-4 h-4 mr-2 animate-spin" fill="none" viewBox="0 0 24 24">
                          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
                        </svg>
                        Checking...
                      {:else}
                        <Icon icon="mdi:check" class="mr-2" width="16" />
                        Verify Webhook
                      {/if}
                    </button>
                    <button
                      on:click={() => markGitLabStepComplete('configure-webhook')}
                      class="border border-[var(--sg-warning)] text-[var(--sg-warning)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-warning-bg)]"
                    >
                      Skip Verification
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabStep === 'configure-variables'}
            <div class="bg-[var(--sg-purple-bg)] rounded-lg p-4 sm:p-6">
              <div class="flex flex-col sm:flex-row sm:items-start gap-4">
                <div class="flex-shrink-0 flex justify-center sm:block">
                  <div class="w-12 h-12 sm:w-10 sm:h-10 bg-[var(--sg-purple)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:cog" class="text-white" width="20" />
                  </div>
                </div>
                <div class="ml-4 flex-1">
                  <h3 class="text-lg font-semibold text-[var(--sg-text)] mb-2">Configure CI/CD Variables</h3>
                  <p class="text-[var(--sg-purple)] mb-4">
                    Configure project settings to allow Terrateam to pass credentials securely to your Terraform runs.
                  </p>

                  <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-purple)]">
                    <div class="space-y-3 text-sm">
                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-1-circle" class="text-[var(--sg-purple)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">Go to your GitLab project CI/CD settings</div>
                          <div class="text-[var(--sg-text-dim)] text-xs">
                            {#if selectedGitLabGroup && manualGitLabProject}
                              <a
                                href="{serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}/{selectedGitLabGroup.name}/{manualGitLabProject}/-/settings/ci_cd"
                                target="_blank"
                                rel="noopener noreferrer"
                                class="inline-flex items-center text-[var(--sg-purple)] hover:underline"
                              >
                                Project → Settings → CI/CD
                                <Icon icon="mdi:open-in-new" class="ml-1" width="12" />
                              </a>
                            {:else}
                              Project → Settings → CI/CD
                            {/if}
                          </div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-2-circle" class="text-[var(--sg-purple)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">Expand the <strong>Variables</strong> section</div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-3-circle" class="text-[var(--sg-purple)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">Find <strong>"Minimum role to use pipeline variables"</strong></div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-4-circle" class="text-[var(--sg-purple)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">Select <strong>Developer</strong> from the dropdown</div>
                          <div class="text-[var(--sg-text-dim)] text-xs">This allows Terrateam to use pipeline variables</div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-5-circle" class="text-[var(--sg-purple)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">Click <strong>Save changes</strong></div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="bg-[var(--sg-warning-bg)] rounded p-3 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:shield-lock" class="text-[var(--sg-warning)] mr-2 mt-0.5" width="16" />
                      <div class="text-sm text-[var(--sg-warning)]">
                        <strong>Important:</strong> This allows Terrateam to run pipelines with variables containing your cloud credentials and Terraform configuration.
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markGitLabStepComplete('configure-variables')}
                      class="bg-[var(--sg-purple)] hover:opacity-90 text-white px-4 py-2 rounded-lg text-sm font-medium"
                    >
                      CI/CD Configured
                    </button>
                    <button
                      on:click={() => goToGitLabStep('configure-webhook')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabStep === 'add-pipeline'}
            <div class="bg-[var(--sg-success-bg)] rounded-lg p-6">
              <div class="flex items-start">
                <div class="flex-shrink-0">
                  <div class="w-10 h-10 bg-[var(--sg-success)] rounded-lg flex items-center justify-center">
                    <Icon icon="mdi:file-code" class="text-white" width="20" />
                  </div>
                </div>
                <div class="ml-4 flex-1">
                  <h3 class="text-lg font-semibold text-[var(--sg-success)] mb-2">Add .gitlab-ci.yml File</h3>
                  <p class="text-[var(--sg-success)] mb-4">
                    Add the Terrateam CI/CD template to your repository to enable Terraform automation.
                  </p>

                  <div class="bg-[var(--sg-bg-1)] rounded-lg p-4 mb-4 border border-[var(--sg-success)]">
                    <div class="space-y-3 text-sm">
                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-1-circle" class="text-[var(--sg-success)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">
                            Create or edit <code class="bg-[var(--sg-bg-2)] px-2 py-1 rounded">.gitlab-ci.yml</code> in
                            {#if selectedGitLabGroup && manualGitLabProject}
                              <a
                                href="{serverConfig?.gitlab?.web_base_url || 'https://gitlab.com'}/{selectedGitLabGroup.name}/{manualGitLabProject}"
                                target="_blank"
                                rel="noopener noreferrer"
                                class="inline-flex items-center font-medium text-[var(--sg-success)] underline hover:text-[var(--sg-success)]"
                              >
                                your repository root
                                <Icon icon="mdi:open-in-new" class="ml-1" width="14" />
                              </a>
                            {:else}
                              your repository root
                            {/if}
                          </div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-2-circle" class="text-[var(--sg-success)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">Add this content:</div>
                          <div class="mt-2 bg-[var(--sg-bg-0)] p-3 rounded border relative">
                            <button
                              on:click={() => {
                                const yamlContent = `# .gitlab-ci.yml - Using the terrateam template
spec:
  inputs:
    TERRATEAM_TRIGGER:
      description: "Is this being triggered by terrateam?"
      type: string
      default: "$TERRATEAM_TRIGGER"
    WORK_TOKEN:
      description: "The work token from terrateam"
      type: string
      default: "$WORK_TOKEN"
    API_BASE_URL:
      description: "The base url for the terrateam api"
      type: string
      default: "$API_BASE_URL"
    RUNS_ON:
      description: "The tags to use for the runner"
      type: array
      default: []
---
include:
  - project: 'terrateam-io/terrateam-template'
    file: 'terrateam-template.yml'
    inputs:
      TERRATEAM_TRIGGER: $[[ inputs.TERRATEAM_TRIGGER ]]
      WORK_TOKEN: $[[ inputs.WORK_TOKEN ]]
      API_BASE_URL: $[[ inputs.API_BASE_URL ]]
      RUNS_ON: $[[ inputs.RUNS_ON ]]

stages:
  - terrateam

terrateam_job:
  extends: .terrateam_template`;
                                navigator.clipboard.writeText(yamlContent);
                                copiedYaml = true;
                                setTimeout(() => copiedYaml = false, 2000);
                              }}
                              class="absolute top-2 right-2 px-2 py-1 {copiedYaml ? 'bg-[var(--sg-success)]' : 'bg-[var(--sg-success)] hover:bg-[var(--sg-success)]'} text-white rounded text-xs flex items-center transition-colors"
                            >
                              <Icon icon={copiedYaml ? "mdi:check" : "mdi:content-copy"} class="mr-1" width="14" />
                              {copiedYaml ? 'Copied!' : 'Copy'}
                            </button>
                            <pre class="text-xs text-[var(--sg-text)] overflow-x-auto pr-16"><code># .gitlab-ci.yml - Using the terrateam template
spec:
  inputs:
    TERRATEAM_TRIGGER:
      description: "Is this being triggered by terrateam?"
      type: string
      default: "$TERRATEAM_TRIGGER"
    WORK_TOKEN:
      description: "The work token from terrateam"
      type: string
      default: "$WORK_TOKEN"
    API_BASE_URL:
      description: "The base url for the terrateam api"
      type: string
      default: "$API_BASE_URL"
    RUNS_ON:
      description: "The tags to use for the runner"
      type: array
      default: []
---
include:
  - project: 'terrateam-io/terrateam-template'
    file: 'terrateam-template.yml'
    inputs:
      TERRATEAM_TRIGGER: $[[ inputs.TERRATEAM_TRIGGER ]]
      WORK_TOKEN: $[[ inputs.WORK_TOKEN ]]
      API_BASE_URL: $[[ inputs.API_BASE_URL ]]
      RUNS_ON: $[[ inputs.RUNS_ON ]]

stages:
  - terrateam

terrateam_job:
  extends: .terrateam_template</code></pre>
                          </div>
                        </div>
                      </div>

                      <div class="flex items-start">
                        <Icon icon="mdi:numeric-3-circle" class="text-[var(--sg-success)] mr-2 mt-0.5" width="16" />
                        <div>
                          <div class="text-[var(--sg-text-muted)]">Commit and push to your default branch</div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <div class="bg-[var(--sg-accent-bg)] rounded p-3 mb-4">
                    <div class="flex items-start">
                      <Icon icon="mdi:information" class="text-[var(--sg-accent)] mr-2 mt-0.5" width="16" />
                      <div class="text-sm text-[var(--sg-accent)]">
                        <strong>Note:</strong> If you already have a .gitlab-ci.yml file, you'll need to integrate these rules with your existing jobs. Contact support for help with complex setups.
                      </div>
                    </div>
                  </div>

                  <div class="flex items-center space-x-3">
                    <button
                      on:click={() => markGitLabStepComplete('add-pipeline')}
                      class="bg-[var(--sg-success)] hover:bg-[var(--sg-success)] text-white px-4 py-2 rounded-lg text-sm font-medium"
                    >
                      Pipeline Added
                    </button>
                    <button
                      on:click={() => goToGitLabStep('configure-variables')}
                      class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-4 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                    >
                      Go Back
                    </button>
                  </div>
                </div>
              </div>
            </div>

          {:else if currentGitLabStep === 'success'}
            <div class="text-center py-12">
              <div class="inline-flex items-center justify-center w-16 h-16 bg-[var(--sg-success-bg)] rounded-full mb-6">
                <Icon icon="mdi:check-circle" class="text-[var(--sg-success)]" width="32" />
              </div>
              <h3 class="text-2xl font-semibold text-[var(--sg-text)] mb-2 flex items-center justify-center">
                <Icon icon="mdi:party-popper" class="text-[var(--sg-purple)] mr-2" width="28" />
                GitLab Setup Complete!
              </h3>
              <p class="text-[var(--sg-text-dim)] mb-6">
                Terrateam is now configured for <strong>{selectedGitLabGroup?.name || 'your GitLab group'}</strong>. You're ready to automate your Terraform workflows!
              </p>

              <div class="bg-[var(--sg-success-bg)] rounded-lg p-6 mb-6 max-w-md mx-auto">
                <h4 class="font-semibold text-[var(--sg-success)] mb-3">What you've set up:</h4>
                <div class="space-y-2 text-sm text-[var(--sg-success)]">
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    GitLab group selected and configured
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    Terrateam bot added as Developer
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    Webhook configured for events
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    CI/CD variables configured
                  </div>
                  <div class="flex items-center">
                    <Icon icon="mdi:check" class="text-[var(--sg-success)] mr-2 flex-shrink-0" width="16" />
                    GitLab CI pipeline added
                  </div>
                </div>
              </div>

              <div class="flex justify-center space-x-4">
                <button
                  on:click={() => window.location.hash = '#/repositories'}
                  class="bg-[var(--sg-bg-2)] hover:bg-[var(--sg-bg-2)] text-white px-6 py-2 rounded-lg text-sm font-medium"
                >
                  View Repositories
                </button>
                <button
                  on:click={() => openExternalLink('https://docs.terrateam.io/')}
                  class="border border-[var(--sg-border)] text-[var(--sg-text-dim)] px-6 py-2 rounded-lg text-sm font-medium hover:bg-[var(--sg-bg-2)]"
                >
                  Read Documentation
                </button>
              </div>
            </div>
          {/if}
        </div>
      {/if}

    </div>

    <!-- Help Section -->
    <div class="text-center mt-8">
      <p class="text-sm text-[var(--sg-text-dim)]">
        Need help? Check the
        <button
          on:click={() => openExternalLink('https://docs.terrateam.io/')}
          class="text-[var(--sg-accent)] hover:underline"
        >
          documentation
        </button>
        or get help on
        <button
          on:click={() => openExternalLink('https://terrateam.io/slack')}
          class="text-[var(--sg-accent)] hover:underline"
        >
          Slack
        </button>.
      </p>
    </div>

  </div>
</PageLayout>
