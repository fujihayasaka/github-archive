# typed: true
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    class Create < ::CloudEnvironments::Command
      class Result
        include ICreateResult
        include GitHub::Memoizer

        sig { params(workbench_cloudspace: Workbench::Cloudspace).void }
        def initialize(workbench_cloudspace)
          @workbench_cloudspace = workbench_cloudspace
        end

        sig { params(workbench_cloudspace: Workbench::Cloudspace).returns(Workbench::Cloudspace) }
        attr_writer :workbench_cloudspace

        sig { params(env: Codespaces::Environment).returns(Codespaces::Environment) }
        attr_writer :env

        sig { params(github_token: String).returns(String) }
        attr_writer :github_token

        sig { params(github_token_valid_after: Float).returns(Float) }
        attr_writer :github_token_valid_after

        sig { override.returns(Workbench::Cloudspace) }
        attr_reader :workbench_cloudspace

        sig { override.returns(T.nilable(Codespaces::Environment)) }
        attr_reader :env

        sig { override.returns(T.nilable(String)) }
        attr_reader :github_token

        sig { override.returns(T.nilable(Float)) }
        attr_reader :github_token_valid_after

        sig { override.returns(T::Boolean) }
        def provisioned?
          return false unless workbench_cloudspace.provisioned?
          !!env&.has_connection?
        end
      end

      include ActiveModel::Validations

      validate :codespace_creation_allowed
      validates_presence_of :repository_id, message: "a repository is required"
      validate :vscs_target_developer_only
      validate :vscs_target_valid
      validate :validate_vscs_target_url
      validate :validate_location
      validates_presence_of :billable_owner, message: "could not be determined for your new spark"
      validate :ensure_owner_can_create
      validate :enforce_per_user_limit
      validate :usage_allowed
      validate :specified_sku_allowed_and_available
      validate :sku_allowed_by_devcontainer_and_policy
      validate :base_image_allowed

      attr_reader :owner, :spark_id, :repository_id, :template_repository_id, :sku_name, :vscs_target_url, :result, :ref, :oid, :operation

      sig do
        params(
          owner: ::User,
          spark_id: String,
          repository_id: Integer,
          operation: Codespaces::AsyncOperation,
          sku_name: T.nilable(String),
          vscs_target: T.nilable(T.any(String, Symbol)),
          vscs_target_url: T.nilable(String),
          concurrency_policy: T.nilable(CloudEnvironments::IConcurrencyLimiter),
          template_repository_id: T.nilable(Integer),
        ).void
      end
      def initialize(
          owner:,
          spark_id:,
          repository_id:,
          operation:,
          sku_name: nil,
          vscs_target: nil,
          vscs_target_url: nil,
          concurrency_policy: nil,
          template_repository_id: nil
        )
        @owner = owner
        @spark_id = spark_id
        @repository_id = repository_id
        @template_repository_id = template_repository_id
        @operation = operation
        @sku_name = sku_name.presence
        @vscs_target = vscs_target
        @vscs_target_url = vscs_target_url
        @concurrency_policy = concurrency_policy
      end

      def valid?(context = nil)
        # It's invalid to call valid? before calling `get_target_ref!` the way things are currently set up.
        get_target_ref!
        super
      end

      sig { override.returns(Result) }
      def perform
        get_target_ref!
        validate!

        sku = Codespaces::Skus.sku_by_name(corrected_attributes[:sku_name])
        @stats_tagger = new_stats_tagger(sku_name: corrected_attributes[:sku_name])

        return create_cloud_environment unless use_concurrency_limiter?

        concurrency_policy.reserve_capacity(sku: sku, location: location) do |has_capacity|
          if has_capacity
            create_cloud_environment
          else
            raise Codespaces::CopilotWorkbenchConcurrencyLimitError
          end
        end
      end

      private

      sig { returns(Result) }
      def create_cloud_environment
        workbench = ::Workbench.load_workbench(owner.id, spark_id)
        corrected_attributes[:spark_workbench_id] = spark_id

        environment_options = {
          # Dials can be modified in stafftools
          autoShutdownDelayMinutes: Workbench::SparkCloudspaces::Dials::IdleTimeout.new(force_cache_miss: true).value,
          spark_runtime_permanent_name: workbench && workbench["runtimePermanentName"] ? workbench["runtimePermanentName"] : nil,
          spark_cloudspace: true
        }

        if owner&.feature_enabled?(:workspace_resume_from_blob)
          if (sas_uri = Workbench::SnapshotBlobs.get_snapshot_upload_uri(spark_id))
            environment_options[:snapshot_blob_sas_uri] = sas_uri
          end
        end

        CloudEnvironments::Public.create(
          attributes: corrected_attributes,
          environment_options: environment_options,
          stats_tagger:,
          entry_point: nil,
          operation:
        ).then do |result|
          @result = Result.new(::Workbench::Cloudspace.new(result.cloud_environment))
          @result.env = result.env
          @result.github_token = result.github_token
          @result.github_token_valid_after = result.github_token_valid_after
          @result
        end

        if workbench
          workbench["cloud_environment_id"] = result&.workbench_cloudspace&.cloud_environment&.id
          ::Workbench.save_workbench(owner.id, spark_id, JSON.dump(workbench))
        end

        @result
      end

      def codespace_creation_allowed
        errors.add(:base, "Codespace creation is temporarily unavailable") if owner&.feature_enabled?(:disable_codespace_creation)
      end

      memoize def vscs_target
        @vscs_target.present? ? @vscs_target.to_sym : Codespaces::Vscs.default_target
      end

      def vscs_target_developer_only
        return unless @vscs_target.present? && @vscs_target != Codespaces::Vscs.default_target

        errors.add(:vscs_target, "specified but owner is not authorized to use this feature") unless owner&.feature_enabled?(:codespaces_developer)
      end

      def vscs_target_valid
        # In order to validate against SKUs properly we need a valid VSCS target
        return unless vscs_target.present?

        errors.add(:vscs_target, "is not a valid value") unless Codespaces::Vscs.valid_target_for_provisioning?(vscs_target&.to_sym)
        errors.add(:vscs_target, "'local' requires a vscs_target_url") if vscs_target.to_s == "local" && vscs_target_url.blank?
      end

      memoize def location
        location = Codespaces::GetRegionForUser.call(
          user: owner,
          repository: repository,
          client: :dotcom,
          vscs_target: vscs_target
        )
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

      def ensure_owner_can_create
        return unless owner && repository

        unless repository_policy.can_attempt_create?
          errors.add(:repository, "does not allow you to create a codespace")
        end
      end

      def enforce_per_user_limit
        # TODO: WorkbenchCloudEnvironment specific logic here
      end

      def input_ref
        return @input_ref if defined?(@input_ref)

        @input_ref = repository&.default_branch
      end

      def repository
        return @repository if defined?(@repository)

        @repository = Repositories::Public.find_active!(repository_id)
      end

      def template_repository
        return @template_repository if defined?(@template_repository)

        @template_repository = Repositories::Public.find_active!(template_repository_id) if template_repository_id
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

      def billable_owner
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
          billable_owner: billable_owner,
          vscs_target: vscs_target,
          devcontainer_path: devcontainer_path,
        )&.name&.to_s
      end

      def retention_period_minutes
        30.days.in_minutes.to_i
      end

      def base_image_allowed
        allowed = Codespaces::ImagePolicy.image_allowed?(
          image_name: devcontainer&.image,
          repository: repository,
          billable_owner: billable_owner
        )

        errors.add(:base_image, "'#{devcontainer&.image}' is disallowed by policy set by your organization or enterprise administrator.") if !allowed
      end

      memoize def devcontainer
        Codespaces::DevContainer.new(repository: repository, oid: @oid, filepath: devcontainer_path) if @oid.present?
      end

      memoize def devcontainer_path
        Codespaces::DevContainer.get_default_path(repository, @oid)
      end

      sig { returns(T.nilable(String)) }
      def sku_with_default
        sku_name || default_sku
      end

      def specified_sku_allowed_and_available # Can this be completely rolled into the other SKU validation?
        return unless sku_name && billable_owner

        unless sku_name.in?(Codespaces::Skus.valid_sku_names)
          errors.add(:sku_name, "'#{sku_name}' is not valid")
        end

        sku = Codespaces::Skus.sku_by_name(sku_name)

        sku_allowed_for_owner = if owner == billable_owner
          sku&.allowed_for_user?(billable_owner)
        else # A billable org may allow further SKUs to the codespace's user.
          sku&.allowed_for_user?(billable_owner) || sku&.allowed_for_user?(owner)
        end

        sku_allowed = if repository.public?
          sku_allowed_for_owner
        else
          sku_allowed_for_repository = sku&.allowed_for_repository?(repository)
          sku_allowed_for_owner || sku_allowed_for_repository
        end
        errors.add(:sku_name, "'#{sku_name}' is not available") unless sku_allowed
      end

      def allowed_sku_names
        return @allowed_sku_names if defined?(@allowed_sku_names)

        allowed_skus = Codespaces::Skus.allowed_for_new_codespace(
          repository: repository,
          owner: owner,
          location: location,
          ref: repository.default_branch,
          billable_owner: billable_owner,
          vscs_target: vscs_target,
          devcontainer_path: devcontainer_path,
        )

        @allowed_sku_names = allowed_skus&.map { |sku| sku.name.to_s }
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
        return unless owner&.user? && billable_owner

        GitHub.tracer.in_span("codespaces/create#usage_allowed", attributes: tags, kind: :internal) do |_span|
          if repository.disabled? || repository.access.disabled?
            errors.add(:usage, "not allowed: repository is disabled")
            return
          end
          if owner.spammy? || billable_owner.spammy? || repository&.owner&.spammy?
            errors.add(:usage, "not allowed")
            return
          end
          # TODO: Add Workbench specific logic
        end
      end

      memoize def corrected_attributes
        {
          owner: owner,
          repository_id: repository.id,
          template_repository_id: template_repository&.id,
          ref: ref,
          oid: oid,
          billable_owner: billable_owner,
          vscs_target: vscs_target,
          retention_period_minutes: retention_period_minutes,
          sku_name: sku_with_default,
          location: corrected_location_for_sku(sku_name),
          plan: existing_provisioned_plan,
          devcontainer_path: devcontainer_path,
        }
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
        @repository_policy ||= Codespaces::RepositoryPolicy.async_with_prefill(owner, repository).sync
      end

      def concurrency_policy
        @concurrency_policy ||= T.let(Codespaces::SparkWorkbenchConcurrencyPolicy.new(owner, billable_owner: billable_owner), T.nilable(CloudEnvironments::IConcurrencyLimiter))
      end

      def use_concurrency_limiter?
        !owner.feature_enabled?(:workbench_concurrency_unlimited)
      end

      sig { params(sku_name: T.nilable(String)).returns(CloudEnvironments::IStatsTagger) }
      def new_stats_tagger(sku_name:)
        Workbench::SparkCloudspaces::StatsTagger.new(
          location: location,
          repository: repository.id,
          spark_id: spark_id,
          vscs_target: vscs_target,
          using_default_sku: !sku_name,
          sku_name: sku_name,
          owner: owner,
        )
      end

      def stats_tagger
        @stats_tagger ||= new_stats_tagger(sku_name: sku_name)
      end
    end
  end
end
