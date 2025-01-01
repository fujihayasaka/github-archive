# typed: true
# frozen_string_literal: true

module WorkspaceEditor
  module Cloudspaces
    class FindOrCreate < CloudEnvironments::Command

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

      attr_reader :owner, :repository_id, :pull_request_number, :location, :display_name, :devcontainer_path, :sku_name, :vscs_target_url, :result, :ref, :oid, :operation, :entry_point

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
        @vscs_target = vscs_target
        @vscs_target_url = vscs_target_url
        @concurrency_policy = concurrency_policy
        @entry_point = entry_point
      end

      # Note: Validations are handled in the respective Find and Create commands
      sig { override.returns(Result) }
      def perform
        found_result = T.let(Find.call(
            owner:,
            repository_id:,
            pull_request_number:,
            vscs_target: @vscs_target,
            entry_point:,
            connect: true,
          ),
        Find::Result)
        if workspace_editor_cloudspace = found_result.workspace_editor_cloudspace
          if workspace_editor_cloudspace.cloud_environment.environment_data&.suspended?
            cloud_environment = workspace_editor_cloudspace.cloud_environment
            # TODO: We should remove this and let CreateUnique handle it when the feature flag for it is removed
            cloud_environment.deprovision! unless cloud_environment.owner&.feature_enabled?(:codespaces_hadron_no_delete_on_shutdown)
          else
            result = Result.new(workspace_editor_cloudspace)
            result.env = found_result.env if found_result.env.present?
            result.found = true

            @operation.mark_as_ended
            return result
          end
        end

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
        result.found = false

        result
      end
    end
  end
end
