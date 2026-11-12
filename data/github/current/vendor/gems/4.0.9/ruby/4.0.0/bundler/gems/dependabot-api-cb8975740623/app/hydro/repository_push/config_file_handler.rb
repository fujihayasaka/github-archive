# frozen_string_literal: true

module RepositoryPush
  class ConfigFileHandler
    attr_reader :ref, :before_sha, :after_sha, :repository, :owner,
                :changed_files, :tenant_id, :tenant_slug, :actor

    GITHUB_NULL_OID = "0" * 40

    def self.run(message)
      ref = message.value.fetch(:ref)
      before_sha = message.value.fetch(:before)
      after_sha = message.value.fetch(:after)
      repository = message.value.fetch(:repository)
      owner = message.value.fetch(:owner)
      changed_files = message.value.fetch(:changed_files)
      actor = message.value[:actor]
      tenant_id = message.headers.fetch("X-GitHub-Tenant-ID") { raise if Dependabot.proxima? }
      tenant_slug = message.headers.fetch("X-GitHub-Tenant") { raise if Dependabot.proxima? }

      new(ref, before_sha, after_sha, repository, owner, changed_files, actor, tenant_id, tenant_slug).run
    end

    # rubocop:disable Metrics/ParameterLists
    def initialize(ref, before_sha, after_sha, repository, owner, changed_files, actor, tenant_id, tenant_slug)
      @ref = ref
      @before_sha = before_sha
      @after_sha = after_sha
      @repository = repository
      @owner = owner
      @changed_files = changed_files
      @actor = actor
      @tenant_id = tenant_id
      @tenant_slug = tenant_slug
    end
    # rubocop:enable Metrics/ParameterLists

    # TODO: Handle race conditions if we receive a config push before the installation
    #       is complete on the account
    # TODO: Handle race conditions if we receive a config push before handling
    #       a repository transfer event
    #   see: https://github.com/github/dependabot-updates/issues/532
    def run
      Dependabot::Exceptions.push(
        "gh.owner.id": owner[:id],
        "gh.repo.id": repository[:id],
      )

      ActiveRecord::Base.connected_to(role: :reading) do
        process_message if should_process_message?

        MetricsClient.increment("consumer.config_file.push_checked", tags: tags)
        MetricsClient.increment("consumer.config_file.change_detected", tags: tags) if config_file_changed?
      end
    end

    private

    def process_message
      # Discard pushes from repositories which have disabled the config file
      return unless repository_has_config_file_enabled?

      if repository_exists?
        enqueue_config_file_sync(account) if default_branch?
        enqueue_config_file_validation(account)
      else
        enqueue_repo_setup(account)
      end
    end

    def should_process_message?
      # Skip pushes made by Dependabot - these are our own PRs
      return false if dependabot_actor?

      # Fast path: no changed files and not an initial commit means nothing to check
      return false if changed_files.empty? && !initial_commit?

      config_changed = MetricsClient.distribution_time("consumer.config_file.config_file_changed_check.time") do
        config_file_changed?
      end
      return true if config_changed

      # initial commits lack "changed_files" information, so we need to consider
      # them as candidates for config file processing
      return false unless default_branch? && initial_commit?

      # Dependabot knows about the repo already, so we should see if their first
      # commit includes a config file
      repository_exists?.tap do |exists|
        MetricsClient.increment("consumer.config_file.initial_commit_processed") if exists
      end
    end

    def default_branch?
      return @default_branch if defined?(@default_branch)

      @default_branch = ref.sub(%r{^refs/heads/}, "") == repository[:default_branch]
    end

    def changed_files_present?
      changed_files.any?
    end

    def initial_commit?
      before_sha == GITHUB_NULL_OID
    end

    def dependabot_actor?
      return false unless actor

      actor[:login] == Dependabot::Application.integration_login
    end

    def config_file_changed?
      return @config_file_changed if defined?(@config_file_changed)

      # Short-circuit: stop at first match instead of building full Set
      MetricsClient.distribution_time("consumer.config_file.config_file_changed.time") do
        @config_file_changed = changed_files.any? do |f|
          FetchConfigFile::CONFIG_FILE_PATHS.include?(f[:current_path]) ||
            FetchConfigFile::CONFIG_FILE_PATHS.include?(f[:previous_path])
        end
      end
    end

    def account
      return @account if defined?(@account)

      @account = Account.find_by(github_id: owner[:id])
    end

    def repository_exists?
      return false unless account
      return @repository_exists if defined?(@repository_exists)

      @repository_exists = account.repos.exists?(github_id: repository[:id])
    end

    # Detect if the repository has enabled config file processing
    def repository_has_config_file_enabled?
      # Currently only forks can disable config file processing,
      # so we avoid calling the monolith unless the message relates to a fork.
      return true unless repository[:is_fork]

      # If a fork was enabled, we'd have set up the account during that process.
      return false unless account

      repo = find_or_stub_repo(repository[:id])
      # If the Repo already has a configuration file in our database, we can defer
      # calling the monolith and handle any changes.
      return true if repo&.using_config_file?

      MetricsClient.distribution_time("consumer.config_file.fetch_repository_settings.time") do
        settings = Dependabot::Application.dependabot_repository_settings_client.get_repository_settings(repo)
        settings.dependabot_config_file_enabled
      end
    end

    # Find the repo in the database or create a stand-in using the github_id
    def find_or_stub_repo(github_id)
      account&.repos&.find_by(github_id: github_id) || OpenStruct.new(github_id: github_id)
    end

    def tags
      {
        default_branch: default_branch?,
        changed_files_present: changed_files_present?,
        initial_commit: initial_commit?,
        config_file_changed: config_file_changed?,
        account_exists: account.present?,
        repository_exists: repository_exists?,
      }
    end

    # enqueue_config_file_sync retrieves the config file from the
    # repository's default branch in GitHub and upserts the relevant
    # UpdateConfig objects.
    def enqueue_config_file_sync(account)
      ResyncRepoConfigFileJob.perform_later(
        account: account,
        repo_name: repository[:name],
        repo_github_id: repository[:id],
        event_source: "hydro.config_file",
      )

      MetricsClient.increment("consumer.config_file.sync_queued", tags: tags)
    end

    # enqueue_config_file_validation creates a GH run-check to give users a CI
    # status on the branch they pushes config file changes to. This runs on all
    # branches.
    def enqueue_config_file_validation(account)
      ValidateConfigFileJob.perform_later(
        account: account,
        repo_github_id: repository[:id],
        sha: after_sha,
      )

      MetricsClient.increment("consumer.config_file.validation_queued", tags: tags)
    end

    # rubocop:disable Metrics/MethodLength
    def enqueue_repo_setup(account)
      if account
        SetupRepoJob.perform_later(
          account: account,
          github_id: repository[:id],
          sha: after_sha,
        )

        MetricsClient.increment("consumer.config_file.repo_setup_queued", tags: tags)
      elsif GitHubHelpers.onboard_account_with_global_app?(github_id: owner[:id])
        SetupAccountAndRepoWithGlobalAppJob.
          perform_later(
            account_github_id: owner[:id],
            repo_github_id: repository[:id],
            tenant_id: tenant_id,
            tenant_slug: tenant_slug,
            event_source: "hydro.config_file",
            sha: after_sha,
          )

        MetricsClient.increment("consumer.config_file.account_setup_queued", tags: tags)
      else
        # Either we've missed setting up the account or we are still processing
        # the account installation. Add a delay to the remediation to reduce the
        # risk of races if we just need to wait for the installation to finish
        # processing
        RemediateAccountAndRepoActivationJob.
          set(wait: 5.seconds).
          perform_later(
            github_repo_id: repository[:id],
            github_account_id: owner[:id],
            event_source: "hydro.config_file",
            sha: after_sha,
          )

        MetricsClient.increment("consumer.config_file.remediate_account_and_repo_activation_queued", tags: tags)
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end
