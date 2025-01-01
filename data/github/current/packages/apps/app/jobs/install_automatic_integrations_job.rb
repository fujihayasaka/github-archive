# typed: true
# frozen_string_literal: true

class InstallAutomaticIntegrationsJob < ApplicationJob
  queue_as :install_automatic_integrations

  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0..3].join(":")
  }

  INSTALL_ON_ALL_REPOS = [] # Passing an empty array to `Integration#install_on` is equivalent to "install on all repos"
  SILENT_ERRORS = %i(spammy_actor spammy_target)

  AppInstallError = Class.new(RuntimeError)
  AppUpdateError  = Class.new(RuntimeError)

  discard_on AppInstallError, AppUpdateError
  retry_on ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique,  wait: :polynomially_longer, attempts: 2
  retry_on_dirty_exit

  resolve_tenant_context do |target_id|
    target = User.find_by(id: target_id)
    next unless target

    target.business
  end

  # Public: install the GitHub App on the Target via the given Trigger
  #
  # target_id       Integer: the ID of the Organization or User on which to
  #                 install the App.
  # integration_id  Integer: the ID of the GitHub App to install.
  # repo_ids        Array of Integers: a list of repositories, owned by the
  #                 target, on which to give the App permission. Supplying
  #                 nil or an empty array will install the App on *all*
  #                 repositories.
  # options         Hash: arbitrary values that will be passed to the
  #                 trigger class after the App has been installed.
  def perform(target_id, integration_id, trigger_id, repo_ids = INSTALL_ON_ALL_REPOS, options = {})
    entry_point = options[:entry_point]
    options = options.stringify_keys
    enqueued_timestamp = options.fetch("enqueued_timestamp", Time.now.to_i)

    @trigger = IntegrationInstallTrigger.find(trigger_id)
    @integration = Integration.find(integration_id)

    @target = User.find_by(id: target_id)
    return Result.failed(self, :deleted_target, @target, @integration) unless @target

    if IntegrationInstallTrigger.latest(integration: @integration, install_type: @trigger.install_type)&.deactivated?
      return Result.failed(self, :deactivated, @target, @integration)
    end

    @installer = @target.organization? ? @target.admins.first : @target
    @repo_ids  = Array(repo_ids)

    unless should_install?(@trigger, @integration, @target, @repo_ids, options)
      return Result.failed(self, :canceled, @target, @integration)
    end

    result = if (installation = @integration.installations.find_by(target: @target))
      with_write do
        add_repositories_to_existing_installation(installation, @repo_ids, @installer, entry_point)
      end
    else
      with_write do
        create_new_installation(@integration, @target, @repo_ids, @installer, trigger_id, entry_point)
      end
    end

    if result.failed?
      # only raise exceptions when running asynchronously
      raise result.exception if result.exception.present? && !GitHub.foreground?
      return result
    end

    with_write do
      if result.already_installed?
        @trigger.integration_already_installed(
          integration: @integration,
          installation: result.installation,
          target: @target,
          installer: @installer,
          repositories: result.repositories,
          options: options,
        )
      else
        # consider passing the result here if/when we start persisting it
        @trigger.after_integration_installed(
          integration: @integration,
          installation: result.installation,
          target: @target,
          installer: @installer,
          repositories: result.repositories,
          options: options,
        )
      end
    end

    mean_time_to_install_ms = (Time.now.to_i - enqueued_timestamp) * 1_000
    track_time_to_install(@integration, mean_time_to_install_ms)

    result
  end

  # Public: Add repositories to an installation.
  #
  # Returns a Boolean, (IntegrationInstallation/nil), and an Array
  def add_repositories_to_existing_installation(installation, repo_ids, editor, entry_point)
    if installation.installed_on_all_repositories?
      return Result.already_installed(self, :installed_on_all_repositories, installation)
    end

    editor_result = if repo_ids != INSTALL_ON_ALL_REPOS
      repo_ids_to_install = (repo_ids - installation.repository_ids(repository_ids: repo_ids))

      # If there aren't any repositories to add, exit early.
      if repo_ids_to_install.empty?
        return Result.already_installed(self, :already_installed, installation, installation_type: "selected")
      end

      repositories = Repositories::Public.load_repositories(repo_ids_to_install)
      if repositories.exists?
        IntegrationInstallation::Editor.append(
          installation,
          repositories: repositories,
          editor: editor,
          performed_automatically: true,
          entry_point: entry_point
        )
      else
        IntegrationInstallation::Editor::Result.success(installation)
      end
    else
      repositories = INSTALL_ON_ALL_REPOS
      IntegrationInstallation::Editor.perform(installation, repositories: INSTALL_ON_ALL_REPOS, editor: editor, entry_point: entry_point)
    end

    unless editor_result.success?
      exception = AppUpdateError.new(editor_result.error)
      return Result.failed(
        self,
        :failed_to_update,
        installation.target,
        installation.integration,
        exception: exception,
      )
    end

    installation_type = repo_ids == INSTALL_ON_ALL_REPOS ? "all" : "selected"

    Result.success(
      self,
      :repositories_added,
      editor_result.installation,
      repositories,
      installation_type: installation_type,
    )
  end

  # Public: Create a new IntegrationInstallation and install a set of repositories.
  #
  # Returns a Boolean, IntegrationInstallation, and an Array
  def create_new_installation(integration, target, repo_ids, installer, trigger_id, entry_point)
    repositories = Repository.find(repo_ids)

    install_result = integration.install_on(
      target,
      repositories: repositories,
      installer: installer,
      trigger_id: trigger_id,
      entry_point: entry_point
    )

    if install_result.success?
      Result.success(self, :installed, install_result.installation, repositories)
    else
      exception = nil
      unless SILENT_ERRORS.include?(install_result.reason)
        exception = AppInstallError.new(install_result.error)
      end
      Result.failed(
        self,
        :failed_to_create,
        target,
        integration,
        reason: install_result.reason,
        exception: exception,
      )
    end
  end

  private

  # Private: Run before installation checks.
  #
  # This callback is optional, and can be used to signal cancelations.
  # See https://github.com/github/github/pull/125211/files#r328366552 for context
  def should_install?(trigger, integration, target, repo_ids, options)
    result = trigger.should_install?(
      integration: integration,
      target: target,
      repositories: Repository.where(id: repo_ids),
      options: options,
    )
    return true if result.nil?
    !!result
  end

  def track_time_to_install(integration, mean_time_to_install_ms)
    tags = ["installation_queue:#{queue_name}", "integration:#{integration.slug}", "owner:#{integration.owner.display_login}"]

    GitHub.dogstats.distribution(
      "jobs.install_automatic_integrations.mean_time_to_install.dist",
      mean_time_to_install_ms,
      tags: tags,
    )
  end
end
