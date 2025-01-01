# typed: true
# frozen_string_literal: true

# Creates a unique workspace editor cloudspace for a given pull request and user
# also factors in things like whether the features are in sync to determine if we should use
# the existing one or purge it and create a new one.
module WorkspaceEditor
  module Cloudspaces
    class CreateUnique < CloudEnvironments::Command

      class Result
        include IFindOrCreateResult
        include GitHub::Memoizer

        sig { params(workspace_editor_cloudspace: WorkspaceEditor::Cloudspace).void }
        def initialize(workspace_editor_cloudspace)
          @workspace_editor_cloudspace = workspace_editor_cloudspace
        end

        sig { params(workspace_editor_cloudspace: WorkspaceEditor::Cloudspace).returns(WorkspaceEditor::Cloudspace) }
        attr_writer :workspace_editor_cloudspace

        sig { params(env: T.nilable(Codespaces::Environment)).returns(T.nilable(Codespaces::Environment)) }
        attr_writer :env

        sig { params(found: T::Boolean).returns(T::Boolean) }
        attr_writer :found

        sig { override.returns(WorkspaceEditor::Cloudspace) }
        attr_reader :workspace_editor_cloudspace

        sig { override.returns(T.nilable(Codespaces::Environment)) }
        attr_reader :env

        sig { override.returns(T::Boolean) }
        def found?
          !!@found
        end
      end

      include ActiveModel::Validations

      attr_reader :owner, :repository_id, :pull_request_number, :location, :display_name, :devcontainer_path, :sku_name, :vscs_target_url, :result, :ref, :oid, :operation, :entry_point, :force_create, :vscs_target, :concurrency_policy

      sig do
        params(
          owner: ::User,
          repository_id: Integer,
          pull_request_number: Integer,
          operation: Codespaces::AsyncOperation,
          location: String,
          display_name: T.nilable(String),
          devcontainer_path: T.nilable(String),
          sku_name: T.nilable(String),
          vscs_target: T.nilable(String),
          vscs_target_url: T.nilable(String),
          concurrency_policy: T.nilable(T.class_of(CloudEnvironments::IConcurrencyLimiter)),
          entry_point: T.nilable(String),
          force_create: T.nilable(T::Boolean),
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
          vscs_target: nil,
          vscs_target_url: nil,
          concurrency_policy: nil,
          entry_point: nil,
          force_create: false
        )
        @owner = owner
        @repository_id = repository_id
        @pull_request_number = pull_request_number
        @operation = operation
        @location = location
        @display_name = display_name
        @devcontainer_path = devcontainer_path.presence
        @sku_name = sku_name.presence
        @vscs_target = vscs_target
        @vscs_target_url = vscs_target_url
        @concurrency_policy = concurrency_policy
        @entry_point = entry_point
        @force_create = force_create
      end

      sig { override.returns(Result) }
      def perform
        find_or_create_result = T.let(FindOrCreate.call(
            owner:,
            repository_id:,
            pull_request_number:,
            operation:,
            location:,
            display_name:,
            devcontainer_path:,
            sku_name:,
            vscs_target:,
            vscs_target_url:,
            concurrency_policy:,
            entry_point:,
          ),
        FindOrCreate::Result)

        @workspace_editor_cloudspace = find_or_create_result.workspace_editor_cloudspace
        if !find_or_create_result.found? || (find_or_create_result.found? && use_found_cloudspace?)
          # Created a new cloudspace or found a usable cloudspace
          result = Result.new(@workspace_editor_cloudspace)
          result.env = find_or_create_result.env if find_or_create_result.env.present?

          if find_or_create_result.found?
            result.found = true
            @operation.mark_as_ended
          end
          result
        else
          # Found a cloudspace but we cannot use it
          @workspace_editor_cloudspace.cloud_environment.deprovision! if delete_on_shutdown?
          create_cloudspace
        end
      end

      def create_cloudspace
        create_result = T.let(Create.call(
          owner:,
          repository_id:,
          pull_request_number:,
          operation:,
          location:,
          display_name:,
          devcontainer_path:,
          sku_name:,
          vscs_target: @vscs_target,
          vscs_target_url:,
          entry_point:,
        ),
        Create::Result)
        result = Result.new(create_result.workspace_editor_cloudspace)
        result.env = create_result.env if create_result.env.present?
        # Even if one was technically found and we force created a new one, `found` here is
        # intended to indicate whether we are returning a found one or a newly created one.
        result.found = false

        result
      end

      def force?
        return true if @force_create

        # We are using this flag to force a new codespace to be created
        owner.feature_enabled?(:hadron_cloudspace_force_create)
      end

      def use_found_cloudspace?
        # If we're forcing creating we want to create a new one, but we should still delete the old one if it exists
        return false if force?

        # The cloudspace we found is suspended so we need a new one. It's currently faster to create a new one than to restart the existing one.
        !environment_suspended?
      end

      def environment_suspended?
        @workspace_editor_cloudspace.cloud_environment.environment_data&.suspended?
      end

      def delete_on_shutdown?
        !@workspace_editor_cloudspace&.cloud_environment.owner&.feature_enabled?(:codespaces_hadron_no_delete_on_shutdown)
      end
    end
  end
end
