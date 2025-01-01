# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Create < Command
    extend T::Sig
    include ActiveModel::Validations
    include Codespaces::RateLimitable

    validate :ensure_owner_is_user
    validate :codespace_creation_allowed
    validate :require_ref_or_pull
    validate :vscs_target_developer_only
    validate :vscs_target_valid
    validate :validate_vscs_target_url
    validate :validate_location
    validates_presence_of :location
    validates_presence_of :billable_owner, message: "could not be determined for a new codespace"
    validates_presence_of :repository, message: "is missing, please ensure you specified a repository or pull request"
    validates_presence_of :ref, message: "is missing, please ensure you specified a valid ref (branch name or commit SHA) or pull request"
    validates_presence_of :oid, message: "is missing, please ensure you specified a valid ref (branch name or commit SHA) or pull request"
    validate :ensure_owner_can_create
    validate :enforce_per_user_limit
    validate :usage_allowed
    validate :specified_sku_allowed_and_available
    validate :sku_allowed_by_devcontainer_and_policy
    validate :billable_owner_is_expected
    validate :base_image_allowed
    validate :closed_prs_disallowed
    validate :ensure_copilot_workspace_access
    validates_length_of :display_name, maximum: 48, message: "must be 48 characters or less"
    validates_numericality_of :retention_period_minutes,
      allow_nil: true,
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: Codespace::MAX_RETENTION_PERIOD,
      message: "must be between 0 and #{Codespace::MAX_RETENTION_PERIOD}"

    class Result
      attr_accessor :codespace, :env, :github_token, :github_token_valid_after

      def provisioned?
        !!codespace&.provisioned? && env
      end

      def connection_details
        env && env["connection"]
      end
    end

    # `codespace` must be defined set tags in Codespaces::Command parent class
    delegate :codespace, to: :result

    # Feature flags in this list will be added to the body of VSCS create environment requests
    # For example: using `codespaces_new_feature` will include the flag in the request body as:
    # `body["experimentalFeatures"]["codespacesNewFeature"] = true`
    EXPERIMENTAL_FEATURE_FLAGS = %w[]

    REPO_TIMEOUTS = {
      "microsoft/vscode" => 4.hours.in_minutes.to_i,
      "github/github" => 9.hours.in_minutes.to_i,
    }

    attr_reader :attributes, :environment_options, :request_cascade_token, :result, :ref, :oid, :operation

    # `attributes` - a hash or permitted ActionController::Parameters
    def initialize(attributes:, environment_options: {}, user_session: nil, cap_filter: nil, request_cascade_token: false, provisioner: Codespaces::ProvisionEnvironment, concurrency_policy: nil, expected_billable_owner_id: nil, entry_point: nil, operation: nil)
      @attributes = attributes
      @environment_options = environment_options
      @user_session = user_session
      @cap_filter = cap_filter
      @request_cascade_token = request_cascade_token
      @result = Result.new
      @provisioner = provisioner
      @concurrency_policy = concurrency_policy
      @expected_billable_owner_id = expected_billable_owner_id
      @entry_point = entry_point
      @operation = operation
    end

    def valid?(context = nil)
      # It's invalid to call valid? before calling `get_target_ref!` the way things are currently set up.
      get_target_ref!
      super
    end

    def perform
      with_rate_limiting(@attributes[:owner]) do
        get_target_ref!
        validate!

        attrs = corrected_attributes
        sku = Codespaces::Skus.sku_by_name(attrs[:sku_name])
        @stats_tagger = new_stats_tagger(sku_name: attrs[:sku_name])
        result.codespace = concurrency_policy.reserve_capacity(sku: sku, location: location) do |has_capacity|
          if has_capacity || (copilot_workspace? && owner.feature_enabled?(:codespaces_cwtp_no_limits))
            codespace = Codespace.new(attrs)
            codespace.validate!

            # Capture the create attempt *after* we've enforced rate limiting, concurrency limits, and performed
            # validation, and *before* we actually write the record to the database. That way we don't count invalid
            # requests but we do count attempts that fail because the database is unavailable.
            GitHub.dogstats.increment("codespace.created", tags: dd_tags)
            GitHub.dogstats.distribution("codespace.created.dist", 1, tags: dd_tags)

            GitHub.logger.info(
              "codespace.created",
              "gh.catalog_service" => "github/codespaces",
              "gh.codespaces.name" =>  codespace.name,
              "gh.codespaces.id" => codespace.id,
              "gh.codespaces.billable_owner_login" => codespace.billable_owner&.login, # rubocop:disable GitHub/DoNotAllowLogin
              "gh.codespaces.owner_login" => codespace.owner&.login, # rubocop:disable GitHub/DoNotAllowLogin
              "gh.repo.name_with_owner" => codespace.repository&.nwo, # rubocop:disable GitHub/DoNotAllowNameWithOwner
              "gh.codespaces.region" => location,
            )
            codespace.save!

            if operation
              operation.update(codespace: codespace)
              operation.mark_as_started
            end

            codespace.track_pr_source!
            codespace.merge_environment_data!({ state: Codespaces::Vscs::State::CREATED })
            codespace
          else
            if copilot_workspace?
              raise Codespaces::CopilotWorkspaceConcurrencyLimitError
            else
              raise Codespaces::ConcurrencyLimitError
            end
          end
        end
      end

      # Immediately schedule this so that if we're interrupted by a GLB timeout while doing the synchronous
      # provision we'll still have a chance to retry provisioning.
      CodespacesProvisionJob.perform_after_waiting_period(
        waiting_period: GitHub.default_request_timeout,
        codespace: codespace,
        environment_options: environment_options_for_repo,
        entry_point: @entry_point
      )

      GitHub.tracer.in_span("codespaces/create#perform_sync", attributes: tags, kind: :internal) do |span|
        generate_github_token!
        result.env = provision!
        span.set_attribute("gh.codespaces.immediately_connected", result.env["connection"].present?) if result.env
      end

      result
    end

    private

    def owner
      @owner ||= attributes[:owner]
    end

    def location
      @location ||= attributes[:location]
    end

    def display_name
      @display_name ||= attributes[:display_name]
    end

    def provision!
      @provisioner.call(
        codespace,
        skip_find: true, # We know we need to create the environment, so save time & don't try to find it first.
        environment_options: environment_options_for_repo,
        github_token: result.github_token,
        request_cascade_token: request_cascade_token
      )
    rescue *CodespacesProvisionJob::ALL_RETRYABLE_ERRORS => e
      # Retry as a job that can auto-handle a lot of these failure modes, and handle "true failure" properly.
      GitHub.dogstats.increment("codespaces.create.synchronous.retryable_failure", tags: dd_tags.concat(["error:#{e.class.name}"]))
      GitHub.dogstats.distribution("codespaces.create.synchronous.retryable_failure.dist", 1, tags: dd_tags.concat(["error:#{e.class.name}"]))
      nil
    rescue => e # rubocop:todo Lint/GenericRescue
      codespace.failed!
      if operation
        operation.mark_as_failed(failure_reason: e)
      end
      raise
    end

    def generate_github_token!
      github_token, github_token_valid_after = Codespaces::Tokens.mint_github_token_with_estimated_validity(codespace.owner, codespace, entry_point: @entry_point)
      result.github_token = github_token
      result.github_token_valid_after = github_token_valid_after
    end

    def codespace_creation_allowed
      errors.add(:base, "Codespace creation is temporarily unavailable") if owner&.feature_enabled?(:disable_codespace_creation)
    end

    def require_ref_or_pull
      errors.add(:base, "Must specify a ref or pull request, but not both") if !(attributes[:ref].present? ^ attributes[:pull_request_id].present?)
    end

    def devcontainer_path
      @devcontainer_path ||= attributes[:devcontainer_path]
    end

    def vscs_target
      @vscs_target ||= attributes[:vscs_target].present? ? attributes[:vscs_target].to_sym : Codespaces::Vscs.default_target
    end

    def vscs_target_developer_only
      return unless attributes[:vscs_target].present?

      errors.add(:vscs_target, "specified but owner is not authorized to use this feature") unless owner&.feature_enabled?(:codespaces_developer)
    end

    def vscs_target_valid
      # In order to validate against SKUs properly we need a valid VSCS target
      return unless vscs_target.present?

      errors.add(:vscs_target, "is not a valid value") unless Codespaces::Vscs.valid_target_for_provisioning?(vscs_target&.to_sym)
      errors.add(:vscs_target, "'local' requires a vscs_target_url") if vscs_target.to_s == "local" && attributes[:vscs_target_url].blank?
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
      return unless attributes[:vscs_target_url].present?

      if !owner&.feature_enabled?(:codespaces_developer)
        errors.add(:vscs_target_url, "specified but owner is not authorized to use this feature")
      elsif vscs_target.to_s != "local"
        errors.add(:vscs_target, "must be 'local' to specify a devstamp URL")
      end

      uri = URI.parse(attributes[:vscs_target_url])
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
      return unless owner && repository

      unless repository_policy.can_attempt_create?
        errors.add(:repository, "may not be used for a codespace")
      end
    end

    def copilot_workspace?
      attributes[:copilot_workspace_id].present?
    end

    def ensure_copilot_workspace_access
      if copilot_workspace? && owner && !owner.feature_enabled?(:copilot_workspace)
        raise Codespaces::CopilotWorkspaceFeatureDisabledError
      end
    end

    def enforce_per_user_limit
      return enforce_per_user_limit_for_cwtp if copilot_workspace? && !owner.feature_enabled?(:codespaces_cwtp_no_limits)
      return unless owner && Codespaces::Query.new(current_user: owner).at_limit?(billable_owner)
      codespaces_limit = Codespaces::Policy.codespaces_limit(owner)
      if billable_owner.feature_enabled?(:codespaces_enterprise_policies) && billable_owner.in_codespaces_salus_beta?
        org_codespaces_limit, policy_owner = Codespaces::MaximumCreationPolicy.get_limit_and_policy_owner(billable_owner)
      else
        org_codespaces_limit = Codespaces::MaximumCreationPolicy.get_applicable_creations_limit(billable_owner)
        policy_owner = billable_owner
      end

      if !org_codespaces_limit.nil? && Codespaces::Query.new(current_user: owner).all_accessible_codespaces_for_org(billable_owner).count >= org_codespaces_limit
        GitHub.dogstats.increment("codespaces.policy_enforcement.failed_create", tags: dd_tags.concat(["policy_constraint:#{Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS}"]))
        errors.add(:base, "Limit of #{org_codespaces_limit} #{'codespace'.pluralize(org_codespaces_limit)} based on a policy set by '#{policy_owner}' is reached. Delete an existing codespace owned by '#{policy_owner}' to create a new one")
      else
        errors.add(:base, "Limit of #{codespaces_limit} codespaces reached, delete one of your existing codespaces to create a new one")
      end
    end

    def enforce_per_user_limit_for_cwtp
      cwtp_codespace_count = owner.codespaces.visible_to_copilot_workspace(owner).count
      dial = Codespaces::Dials::MaximumTotalCopilotWorkspaceCodespacesForUser.new(force_cache_miss: true)
      cwtp_codespace_limit = dial.value
      if cwtp_codespace_count >= cwtp_codespace_limit
        errors.add(:base, "Limit of Copilot Workspaces reached.")
      end
    end

    def pull_request
      return @pull_request if defined?(@pull_request)

      if pull_request_id = attributes[:pull_request_id].presence
        @pull_request = PullRequest.find(pull_request_id)
      else
        @pull_request = nil
      end
    end

    def input_ref
      return @input_ref if defined?(@input_ref)

      @input_ref = attributes[:ref].presence || pull_request&.head_ref
    end

    def repository
      return @repository if defined?(@repository)
      if attributes[:repository_id]
        # If we have a PR we should just use its `head_repository` as our base repo
        # effectively ignoring any supplied `repository_id`. We could validate this
        # but that seems unnecessary if we can just ignore the `repository_id`.
        @repository = pull_request&.head_repository || Repositories::Public.find_active!(attributes[:repository_id])
      else
        raise ArgumentError, "`repository_id` required"
      end
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
      @billable_owner ||= Codespaces::RepositoryPolicy.async_with_prefill(owner, repository).sync.billable_owner
    end

    sig { returns(T.nilable(String)) }
    def default_machine
      return if errors.where(:vscs_target).any? # We can't find a default machine if we don't know the target.
      return if errors.where(:location).any? # We can't find a default sku if we don't have a valid location.
      return @default_machine if defined?(@default_machine)

      @default_machine = Codespaces::Skus.default_sku(
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
      return unless billable_owner

      # Return early the min retention period for Copilot Workspace codespaces
      if copilot_workspace?
        return 1.day.in_minutes.to_i
      end

      Codespaces::MaximumRetentionPeriodPolicy.get_applicable_retention_period(
        user: owner,
        repository: repository,
        billable_owner: billable_owner,
        requested_retention_period_minutes: attributes[:retention_period_minutes]
      )
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
    def sku_name
      return nil unless attributes[:sku_name].present?

      attributes[:sku_name].to_s
    end

    sig { returns(T.nilable(String)) }
    def machine
      return nil unless attributes[:machine].present?

      attributes[:machine].to_s
    end

    sig { returns(T.nilable(String)) }
    def sku_or_machine
      sku_name || machine
    end

    sig { returns(T.nilable(String)) }
    def sku_or_machine_with_default
      sku_or_machine || default_machine
    end

    def specified_sku_allowed_and_available # Can this be completely rolled into the other SKU validation?
      return unless sku_or_machine && billable_owner

      field = sku_name ? :sku_name : :machine

      unless sku_or_machine.in?(Codespaces::Skus.valid_sku_names)
        errors.add(field, "'#{sku_or_machine}' is not valid")
      end

      sku = Codespaces::Skus.sku_by_name(sku_or_machine)
      sku_allowed = if owner == billable_owner
        sku&.allowed_for_user?(billable_owner)
      else # A billable org may allow further SKUs to the codespace's user.
        sku&.allowed_for_user?(billable_owner) || sku&.allowed_for_user?(owner)
      end
      errors.add(field, "'#{sku_or_machine}' is not available") unless sku_allowed
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

      field = sku_name ? :sku_name : :machine

      if !sku_or_machine_with_default
        # No sku/machine were specified and we didn't find a default either. This should only happen because of
        # overly-restrictive devcontainer host requirements, org policies, or both.
        errors.add(:base, Codespaces::Skus::NO_VALID_MACHINE_TYPES_CATCHALL_MESSAGE)
      elsif !allowed_sku_names.include?(sku_or_machine_with_default)
        # If we have a machine we need to check that it is valid for the declarative SKUs for this repository.
        errors.add(field, "'#{sku_or_machine_with_default}' is not allowed for this repository")
      end
    end

    def usage_allowed
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
        allowed_result = Codespaces::AccessChecker.new(billable_owner, user: owner, repository:, copilot_workspace: copilot_workspace?).run_check(sku_name: sku_or_machine)
        return if allowed_result.allowed?

        owner_is_billable = owner == billable_owner
        message = if copilot_workspace? && allowed_result.disallowed_by_entitlements?
          "not allowed: user #{owner.display_login} has exhausted their allowed Copilot Workspace usage"
        elsif owner_is_billable && allowed_result.disallowed_by_payment_method?
          "not allowed: user #{owner.display_login} does not have a valid payment method"
        elsif owner_is_billable && allowed_result.disallowed_by_spending_limit?
          "not allowed: user #{owner.display_login} is at their spending limit"
        else
          "not allowed: #{billable_owner.display_login} cannot be billed for new codespaces"
        end
        errors.add(:usage, message)
      end
    end

    def billable_owner_is_expected
      if @expected_billable_owner_id && @expected_billable_owner_id != billable_owner&.id
        errors.add(:billable_owner, "has changed")
      end
    end

    def corrected_attributes
      attrs = attributes.merge({
        repository_id: repository.id,
        ref: ref,
        oid: oid,
        billable_owner: billable_owner,
        vscs_target: vscs_target,
        retention_period_minutes: retention_period_minutes,
      })
      if attrs[:pull_request_id].blank?
        pull = Codespaces::FindPullRequest.call(owner: attrs[:owner], repository: repository, ref: attrs[:ref])
        attrs[:pull_request_id] = pull&.id
      end
      attrs.delete(:sku_name)
      attrs.delete(:machine)
      attrs[:sku_name] = sku_or_machine_with_default
      # correct region assignment after last SKU assignment
      attrs[:location] = corrected_location_for_sku(attrs[:sku_name])
      # correct plan after final region assignment
      attrs[:plan] = existing_provisioned_plan
      attrs[:devcontainer_path] = attrs[:devcontainer_path].presence
      attrs
    end

    def environment_options_for_repo
      environment_options.tap do |options|
        options[:autoShutdownDelayMinutes] = if REPO_TIMEOUTS.key?(repository.name_with_owner) && !owner&.feature_enabled?(:codespaces_timeout_override_skip) # rubocop:disable GitHub/DoNotAllowNameWithOwner
          [REPO_TIMEOUTS[repository.name_with_owner], owner.codespace_default_idle_timeout].compact.max # rubocop:disable GitHub/DoNotAllowNameWithOwner
        else
          Codespaces::MaximumIdleTimeoutPolicy.get_applicable_idle_timeout(
            user: owner,
            billable_owner: billable_owner,
            repository: repository,
            requested_idle_timeout_minutes: options[:requestedIdleTimeoutMinutes],
            codespace_id: codespace.id
          )
        end

        experimental_features = {}
        EXPERIMENTAL_FEATURE_FLAGS.each do |flag|
          if repository&.feature_enabled?(flag)
            vscs_flag_name = flag.remove("codespaces_").camelize(:lower).to_sym
            experimental_features[vscs_flag_name] = true
          end
        end

        options[:experimentalFeatures] = experimental_features if experimental_features.present?
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
      @repository_policy ||= Codespaces::RepositoryPolicy.async_with_prefill(owner, repository, ref: input_ref).sync
    end

    def concurrency_policy
      @concurrency_policy ||= if copilot_workspace? && !owner.feature_enabled?(:codespaces_cwtp_no_limits)
        Codespaces::CopilotWorkspaceConcurrencyPolicy.new(owner, billable_owner: billable_owner)
      else
        Codespaces::ConcurrencyPolicy.new(owner, billable_owner: billable_owner)
      end
    end

    def new_stats_tagger(sku_name:)
      Codespaces::StatsTagger.new(
        location: location,
        repository: attributes[:repository_id],
        pull_request: attributes[:pull_request_id],
        vscs_target: vscs_target,
        using_default_sku: !sku_or_machine,
        sku_name: sku_name,
        from_pr: !attributes[:pull_request_id].blank?,
        from_fork: repository&.fork?,
        repo_empty: repository&.empty?,
        owner: attributes[:owner],
        use_prebuild: Codespaces::Prebuilds.configured?(repository),
        is_copilot_workspace: copilot_workspace?,
      )
    end

    def stats_tagger
      @stats_tagger ||= new_stats_tagger(sku_name: sku_or_machine)
    end

    def dd_tags
      tags = super
      tags << "codespaces_use_storage_v2_internal:true" if use_storage_v2_internal?
      tags
    end

    def use_storage_v2_internal?
      return false unless attributes[:owner]&.feature_enabled?(:codespaces_developer)
      storage_v2_enabled = [repository, attributes[:owner]].all? do |entity|
        entity&.feature_enabled?(:codespaces_use_storage_v2)
      end

      force_storage_v2_enabled = [repository, attributes[:owner]].any? do |entity|
        entity&.feature_enabled?(:codespaces_force_storage_v2)
      end

      storage_v2_enabled || force_storage_v2_enabled
    end
  end
end
