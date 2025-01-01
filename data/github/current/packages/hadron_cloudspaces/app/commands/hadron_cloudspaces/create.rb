# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  class Create < CloudEnvironments::Command
    class Result
      include ICreateResult
      include GitHub::Memoizer
      extend T::Sig

      sig { params(hadron_cloudspace: HadronCloudspace).returns(HadronCloudspace) }
      attr_writer :hadron_cloudspace

      sig { params(env: Codespaces::Environment).returns(Codespaces::Environment) }
      attr_writer :env

      sig { params(github_token: String).returns(String) }
      attr_writer :github_token

      sig { params(github_token_valid_after: Float).returns(Float) }
      attr_writer :github_token_valid_after

      sig { override.returns(T.nilable(HadronCloudspace)) }
      attr_reader :hadron_cloudspace

      sig { override.returns(T.nilable(Codespaces::Environment)) }
      attr_reader :env

      sig { override.returns(T.nilable(String)) }
      attr_reader :github_token

      sig { override.returns(T.nilable(Float)) }
      attr_reader :github_token_valid_after

      sig { override.returns(T::Boolean) }
      def provisioned?
        return false unless hadron_cloudspace&.provisioned?
        !!env&.has_connection?
      end
    end

    class HadronFeatureDisabledError < StandardError
      include HadronCloudspaces::IFeatureDisabledError
    end

    extend T::Sig
    include ActiveModel::Validations

    validate :ensure_owner_is_user
    validate :codespace_creation_allowed
    validates_presence_of :repository_id, message: "a repository is required"
    validates_presence_of :pull_request_number, message: "a pull request is required"
    validates_presence_of :pull_request, message: "could not be found and is required"
    validate :vscs_target_developer_only
    validate :vscs_target_valid
    validate :validate_vscs_target_url
    validate :validate_location
    validates_presence_of :location
    validates_presence_of :billable_owner, message: "could not be determined for a new codespace"
    validates_presence_of :repository, message: "is missing, please ensure you specified a repository or pull request"
    validates_presence_of :ref, message: "is missing, please ensure you specified a valid ref (branch name or commit SHA) or pull request"
    validates_presence_of :oid, message: "is missing, please ensure you specified a valid ref (branch name or commit SHA) or pull request"
    validate :hadron_allowed
    validate :ensure_owner_can_create
    validate :enforce_per_user_limit
    validate :usage_allowed
    validate :specified_sku_allowed_and_available
    validate :sku_allowed_by_devcontainer_and_policy
    validate :base_image_allowed
    validate :closed_prs_disallowed
    validates_length_of :display_name, maximum: 48, message: "must be 48 characters or less"
    validates_numericality_of :retention_period_minutes,
      allow_nil: true,
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: ::Codespace::MAX_RETENTION_PERIOD,
      message: "must be between 0 and #{::Codespace::MAX_RETENTION_PERIOD}"

    attr_reader :owner, :repository_id, :pull_request_number, :location, :display_name, :devcontainer_path, :sku_name, :vscs_target_url, :result, :ref, :oid, :operation

    sig do
      params(
        owner: User,
        repository_id: Integer,
        pull_request_number: Integer,
        operation: Codespaces::AsyncOperation,
        location: String,
        display_name: T.nilable(String),
        devcontainer_path: T.nilable(String),
        sku_name: T.nilable(String),
        retention_period_minutes: T.nilable(Integer),
        vscs_target: T.nilable(String),
        vscs_target_url: T.nilable(String),
        concurrency_policy: T.nilable(CloudEnvironments::IConcurrencyLimiter),
        entry_point: T.nilable(T.any(String, Symbol)),
      ).void
    end
    def initialize(
        owner:,
        repository_id:,
        pull_request_number:,
        operation:,
        location:,
        display_name: nil,
        devcontainer_path: nil,
        sku_name: nil,
        retention_period_minutes: nil,
        vscs_target: nil,
        vscs_target_url: nil,
        concurrency_policy: nil,
        entry_point: nil
      )
      @owner = owner
      @repository_id = repository_id
      @pull_request_number = pull_request_number
      @operation = operation
      @location = location
      @display_name = display_name
      @devcontainer_path = devcontainer_path.presence
      @sku_name = sku_name.presence
      @retention_period_minutes = retention_period_minutes
      @vscs_target = vscs_target
      @vscs_target_url = vscs_target_url
      @result = Result.new
      @concurrency_policy = concurrency_policy
      @entry_point = entry_point
    end

    def valid?(context = nil)
      # It's invalid to call valid? before calling `get_target_ref!` the way things are currently set up.
      get_target_ref!
      super
    end

    def perform
      # We likely want some rate limiting but the regular one is currently implemented as a module that we include
      # so we'd either need a new module to include here or make it an object we can use instead.
      # with_rate_limiting(@attributes[:owner]) do
      get_target_ref!
      validate!

      sku = Codespaces::Skus.sku_by_name(corrected_attributes[:sku_name])
      @stats_tagger = new_stats_tagger(sku_name: corrected_attributes[:sku_name])

      return create_cloud_environment unless use_concurrency_limiter?

      concurrency_policy.reserve_capacity(sku: sku, location: location) do |has_capacity|
        if !has_capacity
          # Delete the least recently used codespace to make room for the new one.
          least_recently_used = owner.codespaces.visible_to_task_cloud_environments(owner).find_all { |c| c.consuming_compute? }.sort_by(&:last_used_at).first
          least_recently_used.deprovision! if least_recently_used
          GitHub.dogstats.increment("codespaces.create_task_cloud_environment.concurrency_limit_reached", tags: tags)
        end
        # TODO: Create the TaskCloudEnvironment CloudExperience model here first. Possibly need a transaction to ensure if the next call fails
        # we can clean up the CloudExperience model we create here. Transactions are a bit dicey though...
        create_cloud_environment
      end
    end

    private

    def create_cloud_environment
      CloudEnvironments::Public.create(attributes: corrected_attributes,
        environment_options: environment_options_for_repo,
        stats_tagger:,
        entry_point: @entry_point,
        operation:
      ).then do |result|
        @result.hadron_cloudspace = HadronCloudspace.new(result.cloud_environment)
        @result.env = result.env
        @result.github_token = result.github_token
        @result.github_token_valid_after = result.github_token_valid_after
        @result
      end
    end

    def codespace_creation_allowed
      # TODO: Is this the right feature flag?
      errors.add(:base, "Codespace creation is temporarily unavailable") if owner&.feature_enabled?(:disable_codespace_creation)
    end

    def hadron_allowed
      raise HadronFeatureDisabledError, "You do not have access to this feature." unless owner&.feature_preview_enabled?(:copilot_hadron_editor)
    end

    memoize def vscs_target
      @vscs_target.present? ? @vscs_target.to_sym : Codespaces::Vscs.default_target
    end

    def vscs_target_developer_only
      return unless @vscs_target.present?

      errors.add(:vscs_target, "specified but owner is not authorized to use this feature") unless owner&.feature_enabled?(:codespaces_developer)
    end

    def vscs_target_valid
      # In order to validate against SKUs properly we need a valid VSCS target
      return unless vscs_target.present?

      errors.add(:vscs_target, "is not a valid value") unless Codespaces::Vscs.valid_target_for_provisioning?(vscs_target&.to_sym)
      errors.add(:vscs_target, "'local' requires a vscs_target_url") if vscs_target.to_s == "local" && vscs_target_url.blank?
    end

    def validate_location
      if vscs_target && Codespaces::Vscs.valid_target_for_provisioning?(vscs_target&.to_sym)
        return if Codespaces::VscsServiceStamp.where(available_for_creates_to: owner).find(region: location, vscs_target:).present?
      else
        # When faced with an invalid vscs_target like "unicorns" the old code would effectively just completely
        # ignore the target and validate against _all_ regions without restriction so this mirrors what we
        # were already doing.
        return if Codespaces::Locations::Region.where(available_for_creates_to: owner).find(location).present?
      end
      errors.add(:location, "is invalid")
    end

    def validate_vscs_target_url
      return unless vscs_target_url.present?

      if !owner&.feature_enabled?(:codespaces_developer)
        errors.add(:vscs_target_url, "specified but owner is not authorized to use this feature")
      elsif vscs_target.to_s != "local"
        errors.add(:vscs_target, "must be 'local' to specify a devstamp URL")
      end

      uri = URI.parse(vscs_target_url)
      errors.add(:vscs_target_url, "is not a valid URL") unless %w(http https).include?(uri.scheme) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(:vscs_target_url, "is not a valid URL")
    end

    sig { params(sku: T.nilable(String)).returns(String) }
    def corrected_location_for_sku(sku)
      return location unless sku
      Codespaces::GetLocationForSKU.call(location:, sku_name: sku, vscs_target:, user: owner).tap { @location = _1 }
    end

    def ensure_owner_is_user
      return unless owner

      errors.add(:owner, "must be a user") unless owner.try(:user?)
    end

    def ensure_owner_can_create
      # TODO: Not sure what this check should be.
      return unless owner && repository

      unless repository_policy.can_attempt_create?
        errors.add(:repository, "may not be used for a codespace")
      end
    end

    def enforce_per_user_limit
      # TODO: TaskCloudEnvironment specific logic here
    end

    def pull_request
      return @pull_request if defined?(@pull_request)

      @pull_request = PullRequests::PullRequestAccessor.new.by_number(repository_id: repository_id, number: pull_request_number)
    end

    def input_ref
      return @input_ref if defined?(@input_ref)

      @input_ref = pull_request&.head_ref
    end

    def repository
      return @repository if defined?(@repository)

      @repository = pull_request&.head_repository
    end

    def get_target_ref!
      return if @ref && @oid
      return unless repository && input_ref

      GitHub.tracer.in_span("codespaces/create#get_target_ref!", attributes: tags, kind: :internal) do
        git_ref = Codespaces::GetTargetRef.call(repository: repository, name_or_oid: input_ref)

        # git_ref can be nil here if we were working with a repository that is
        # `empty?` (e.g. it is not fully created yet on disk).
        @ref, @oid = git_ref&.name, git_ref&.target_oid
      end
    end

    def closed_prs_disallowed
      return unless pull_request && pull_request.closed?

      errors.add(:pull_request, "is not allowed because it is closed.")
    end

    def billable_owner
      # TODO: Is this relevant and correct?
      @billable_owner ||= Codespaces::RepositoryPolicy.async_with_prefill(owner, repository).sync.billable_owner
    end

    sig { returns(T.nilable(String)) }
    def default_sku
      return if errors.where(:vscs_target).any? # We can't find a default sku if we don't know the target.
      return if errors.where(:location).any? # We can't find a default sku if we don't have a valid location.
      return @default_sku if defined?(@default_sku)

      @default_sku = Codespaces::Skus.default_sku(
        repository: repository,
        owner: owner,
        location: location,
        ref: input_ref,
        billable_owner: billable_owner,
        vscs_target: vscs_target,
        devcontainer_path: devcontainer_path,
      )&.name&.to_s
    end

    def retention_period_minutes
      # We delete on shutdown anyway but just in case
      # Note that Hadron cloudspaces are excluded by default in NotifyOwnerOfExpiringCodespacesJob
      1.day.in_minutes.to_i
    end

    def base_image_allowed
      allowed = Codespaces::ImagePolicy.image_allowed?(
        image_name: devcontainer&.image,
        repository: repository,
        billable_owner: billable_owner
      )

      errors.add(:base_image, "'#{devcontainer&.image}' is disallowed by policy set by your organization or enterprise administrator.") if !allowed
    end

    def devcontainer
      Codespaces::DevContainer.new(repository: repository, oid: @oid, filepath: devcontainer_path) if @oid.present?
    end

    sig { returns(T.nilable(String)) }
    def sku_with_default
      @sku_name || default_sku
    end

    def specified_sku_allowed_and_available # Can this be completely rolled into the other SKU validation?
      return unless @sku_name && billable_owner

      unless sku_name.in?(Codespaces::Skus.valid_sku_names)
        errors.add(:sku_name, "'#{@sku_name}' is not valid")
      end

      sku = Codespaces::Skus.sku_by_name(@sku_name)
      sku_allowed = if owner == billable_owner
        sku&.allowed_for_user?(billable_owner)
      else # A billable org may allow further SKUs to the codespace's user.
        sku&.allowed_for_user?(billable_owner) || sku&.allowed_for_user?(owner)
      end
      errors.add(:sku_name, "'#{@sku_name}' is not available") unless sku_allowed
    end

    def allowed_sku_names
      return @allowed_sku_names if defined?(@allowed_sku_names)

      @allowed_sku_names = Codespaces::Skus.allowed_skus_for_new_codespace_with_owner_and_billable_owner(
        repository: repository,
        owner: owner,
        location: location,
        ref: input_ref,
        billable_owner: billable_owner,
        vscs_target: vscs_target,
        devcontainer_path: devcontainer_path,
      )&.map { |sku| sku.name.to_s }
    end

    # Considers devcontainer minimum host requirements ('declarative SKUs') and any enterprise/org policies,
    # which may disallow certain SKUs for the user.
    def sku_allowed_by_devcontainer_and_policy
      return if errors.where(:vscs_target).any? # We can't validate the sku if we don't know the target.
      return if errors.where(:location).any? # We can't validate the sku if we don't have a valid location.

      if !sku_with_default
        # No sku/machine were specified and we didn't find a default either. This should only happen because of
        # overly-restrictive devcontainer host requirements, org policies, or both.
        errors.add(:base, Codespaces::Skus::NO_VALID_MACHINE_TYPES_CATCHALL_MESSAGE)
      elsif !allowed_sku_names.include?(sku_with_default)
        # If we have a machine we need to check that it is valid for the declarative SKUs for this repository.
        errors.add(:sku_name, "'#{sku_with_default}' is not allowed for this repository")
      end
    end

    def usage_allowed
      # TODO: Do we want a completely different AccessChecker for TaskCloudEnvironments?
      return unless owner&.user? && billable_owner

      GitHub.tracer.in_span("codespaces/create#usage_allowed", attributes: tags, kind: :internal) do |_span|
        if owner.feature_enabled?(:codespaces_require_enabled_repository)
          if repository.disabled? || repository.access.disabled?
            errors.add(:usage, "not allowed: repository is disabled")
            return
          end
        end
        if owner.spammy? || billable_owner.spammy? || repository&.owner&.spammy?
          errors.add(:usage, "not allowed")
          return
        end
        # TODO: If we reuse the same AccessChecker we'd have to pass in a different arg to tell it which kind of check to use
        # which is gross. It will need to be refactored to split up its logic and/or allow the billing access checker to
        # be injected from here...
        allowed_result = Codespaces::AccessChecker.new(billable_owner, user: owner, repository:, copilot_workspace: false).run_check(sku_name: sku_name)
        return if allowed_result.allowed?

        owner_is_billable = owner == billable_owner
        message = if owner_is_billable && allowed_result.disallowed_by_payment_method?
          "not allowed: user #{owner.display_login} does not have a valid payment method"
        elsif owner_is_billable && allowed_result.disallowed_by_spending_limit?
          "not allowed: user #{owner.display_login} is at their spending limit"
        else
          "not allowed: #{billable_owner.display_login} cannot be billed for new codespaces"
        end
        errors.add(:usage, message)
      end
    end

    memoize def corrected_attributes
      {
        owner: owner,
        repository_id: repository.id,
        pull_request_id: pull_request.id,
        ref: ref,
        oid: oid,
        billable_owner: billable_owner,
        vscs_target: vscs_target,
        retention_period_minutes: retention_period_minutes,
        sku_name: sku_with_default,
        location: corrected_location_for_sku(@sku_name),
        plan: existing_provisioned_plan,
        devcontainer_path: devcontainer_path,
        copilot_workspace_id: "hadron", # TODO: This is a temporary hack to differentiate TaskCloudEnvironments from other CloudEnvironments
      }
    end

    def environment_options_for_repo
      {}.tap do |options|
        # Hardcoded to 2 hours since its free the COGS is on us.
        options[:autoShutdownDelayMinutes] = 120
      end
    end

    def existing_provisioned_plan
      return @existing_provisioned_plan if defined?(@existing_provisioned_plan)
      attrs = {
          location: location,
          vscs_target: vscs_target,
      }
      @existing_provisioned_plan = Codespaces::Plan.for!(**attrs)
    end

    def repository_policy
      # TODO: Are repository policies different here?
      @repository_policy ||= Codespaces::RepositoryPolicy.async_with_prefill(owner, repository, ref: input_ref).sync
    end

    def concurrency_policy
      @concurrency_policy ||= T.let(HadronCloudspaces::ConcurrencyLimiter.new(owner, billable_owner: billable_owner), T.nilable(CloudEnvironments::IConcurrencyLimiter))
    end

    def use_concurrency_limiter?
      !owner.feature_enabled?(:hadron_concurrency_unlimited) &&
      owner.feature_enabled?(:hadron_concurrency_limiter)
    end

    sig { params(sku_name: T.nilable(String)).returns(CloudEnvironments::IStatsTagger) }
    def new_stats_tagger(sku_name:)
      HadronCloudspaces::StatsTagger.new(
        location: location,
        repository: repository_id,
        pull_request: pull_request_number,
        vscs_target: vscs_target,
        using_default_sku: !sku_name,
        sku_name: sku_name,
        from_pr: true,
        from_fork: repository&.fork?,
        repo_empty: repository&.empty?,
        owner: owner,
        use_prebuild: Codespaces::Prebuilds.configured?(repository),
      )
    end

    def stats_tagger
      @stats_tagger ||= new_stats_tagger(sku_name: sku_name)
    end
  end
end
