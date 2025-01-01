# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  class Find < CloudEnvironments::Command

    class Result
      include GitHub::Memoizer
      extend T::Sig

      sig { params(hadron_cloudspace: HadronCloudspace).returns(HadronCloudspace) }
      attr_writer :hadron_cloudspace

      sig { params(env: Codespaces::Environment).returns(Codespaces::Environment) }
      attr_writer :env

      sig { returns(T.nilable(HadronCloudspace)) }
      attr_reader :hadron_cloudspace

      sig { returns(T.nilable(Codespaces::Environment)) }
      attr_reader :env
    end

    class HadronFeatureDisabledError < StandardError
      include HadronCloudspaces::IFeatureDisabledError
    end

    extend T::Sig
    include ActiveModel::Validations

    validates_presence_of :repository_id, message: "a repository is required"
    validates_presence_of :pull_request_number, message: "a pull request is required"

    # Usage validations
    validate :hadron_allowed
    validate :enforce_per_user_limit, if: [:connect?, :cloud_environment]
    validate :usage_allowed, if: [:connect?, :cloud_environment]

    attr_reader :owner, :repository_id, :pull_request_number, :location, :devcontainer_path, :sku_name, :vscs_target_url, :result, :operation, :entry_point

    sig do
      params(
        owner: User,
        repository_id: Integer,
        pull_request_number: Integer,
        operation: Codespaces::AsyncOperation,
        location: String,
        devcontainer_path: T.nilable(String),
        sku_name: T.nilable(String),
        vscs_target: T.nilable(String),
        vscs_target_url: T.nilable(String),
        concurrency_policy: T.nilable(T.class_of(CloudEnvironments::IConcurrencyLimiter)),
        entry_point: T.nilable(String),
        connect: T::Boolean,
      ).void
    end
    def initialize(
        owner:,
        repository_id:,
        pull_request_number:,
        operation:,
        location:,
        devcontainer_path: nil,
        sku_name: nil,
        vscs_target: nil,
        vscs_target_url: nil,
        concurrency_policy: nil,
        entry_point: nil,
        connect: false
      )
      @owner = owner
      @repository_id = repository_id
      @pull_request_number = pull_request_number
      @operation = operation
      @location = location
      @devcontainer_path = devcontainer_path.presence
      @sku_name = sku_name.presence
      @vscs_target = vscs_target
      @vscs_target_url = vscs_target_url
      @result = Result.new
      @concurrency_policy = concurrency_policy
      @entry_point = entry_point
      @connect = connect
    end

    def perform
      # We likely want some rate limiting but the regular one is currently implemented as a module that we include
      # so we'd either need a new module to include here or make it an object we can use instead.
      # with_rate_limiting(@attributes[:owner]) do
      validate!

      if cloud_environment
        @result.hadron_cloudspace = HadronCloudspace.new(cloud_environment)
        env = fetch_environment! if connect?
        if env.present? && !env.empty?
          @result.env = ::Codespaces::Environment.from_json(env)
        elsif cloud_environment.environment_data.present?
          @result.env = cloud_environment.environment_data
        end
      end
      @result
    end

    private

    memoize def vscs_target
      @vscs_target.present? ? @vscs_target.to_sym : Codespaces::Vscs.default_target
    end

    memoize def cloud_environment
      pull_request = PullRequests::PullRequestAccessor.new.by_number(repository_id: repository_id, number: pull_request_number)
      owner.codespaces.visible_to_task_cloud_environments(owner).where(
        repository_id: repository_id,
        pull_request_id: pull_request.id,
        vscs_target: vscs_target,
        state: %w(pending provisioning provisioned),
      ).first
    end

    def connect?
      !!@connect
    end

    def fetch_environment!
      return unless cloud_environment&.guid
      Codespaces::VscsClient.for_codespace(cloud_environment).fetch_environment!(cloud_environment.guid)
    rescue Codespaces::Client::BadResponseError => e
      # If there is an error fetching from the service we will just ignore it and return the cached data.
      # Client side polling will eventually get the connection data.
      nil
    end

    def billable_owner
      cloud_environment&.billable_owner
    end

    def concurrency_policy
      # TODO: Create and use a TaskCloudEnvironment concurrency policy here.
    end

    def enforce_per_user_limit
      # TODO: TaskCloudEnvironment specific logic here
    end

    def usage_allowed
      return unless cloud_environment.owner&.user?

      if owner.spammy? || !billable_owner || billable_owner.spammy? || cloud_environment.repository&.owner&.spammy?
        errors.add(:usage, "not allowed")
        return
      end

      # TODO: Do we want a completely different AccessChecker for TaskCloudEnvironments?
      usage = Codespaces::AccessChecker.from_codespace(cloud_environment)
      usage_result = usage.run_check(
        sku_name: cloud_environment.sku_name,
        dev_container: cloud_environment.dev_container,
      )
      return if usage_result.allowed?

      error_message = if usage_result.disallowed_by_machine_policy?
        "This codespace is currently using a machine type disallowed by your organization settings. Please update the codespace's machine type or export your changes to a branch."
      elsif usage_result.disallowed_by_image_policy?
        "This codespace uses a dev container image disallowed by your organization settings. Please export your changes to a branch."
      else
        # We should never hit this currently but this is a fallback in case in the future
        # a new kind of AllowedResult error isn't handled.
        "You are not allowed to start this codespace."
      end

      if usage_result.disallowed_by_billing?
        errors.add(:base, :billing, message: error_message)
      elsif usage_result.disallowed_by_machine_policy? || usage_result.disallowed_by_image_policy?
        errors.add(:base, :policy, message: error_message)
      else
        errors.add(:base, message: error_message)
      end
    end

    def hadron_allowed
      raise HadronFeatureDisabledError, "You do not have access to this feature." unless owner && owner.feature_preview_enabled?(:copilot_hadron_editor)
    end

    sig { returns(CloudEnvironments::IStatsTagger) }
    def stats_tagger
      @stats_tagger ||= HadronCloudspaces::StatsTagger.new(
        location: cloud_environment&.location,
        repository: repository_id,
        pull_request: pull_request_number,
        vscs_target: vscs_target,
        using_default_sku: !sku_name,
        sku_name: cloud_environment&.sku_name,
        from_pr: true,
        from_fork: cloud_environment&.repository&.fork?,
        repo_empty: cloud_environment&.repository&.empty?,
        owner: owner,
        use_prebuild: Codespaces::Prebuilds.configured?(cloud_environment&.repository),
        is_task_cloud_environment: true,
      )
    end
  end
end
