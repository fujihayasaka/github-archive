# typed: true
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    class FindOrCreate < CloudEnvironments::Command

      class Result
        include IFindOrCreateResult
        include GitHub::Memoizer

        sig { params(workbench_cloudspace: Workbench::Cloudspace).void }
        def initialize(workbench_cloudspace)
          @workbench_cloudspace = workbench_cloudspace
        end

        sig { params(workbench_cloudspace: Workbench::Cloudspace).returns(Workbench::Cloudspace) }
        attr_writer :workbench_cloudspace

        sig { params(env: T.nilable(Codespaces::Environment)).returns(T.nilable(Codespaces::Environment)) }
        attr_writer :env

        sig { params(found: T::Boolean).returns(T::Boolean) }
        attr_writer :found

        sig { override.returns(Workbench::Cloudspace) }
        attr_reader :workbench_cloudspace

        sig { override.returns(T.nilable(Codespaces::Environment)) }
        attr_reader :env

        sig { override.returns(T::Boolean) }
        def found?
          !!@found
        end
      end

      include ActiveModel::Validations

      attr_reader :owner, :repository_id, :template_repository_id, :spark_id, :devcontainer_path, :sku_name, :vscs_target, :vscs_target_url, :result, :operation

      sig do
        params(
          owner: ::User,
          repository_id: Integer,
          spark_id: String,
          operation: Codespaces::AsyncOperation,
          devcontainer_path: T.nilable(String),
          sku_name: T.nilable(String),
          vscs_target: T.nilable(T.any(String, Symbol)),
          vscs_target_url: T.nilable(String),
          template_repository_id: T.nilable(Integer)
        ).void
      end
      def initialize(
          owner:,
          repository_id:,
          spark_id:,
          operation:,
          devcontainer_path: nil,
          sku_name: nil,
          vscs_target: nil,
          vscs_target_url: nil,
          template_repository_id: nil
        )
        @owner = owner
        @repository_id = repository_id
        @template_repository_id = template_repository_id
        @spark_id = spark_id
        @operation = operation
        @devcontainer_path = devcontainer_path.presence
        @sku_name = sku_name.presence
        @vscs_target = vscs_target
        @vscs_target_url = vscs_target_url
      end

      # Note: Validations are handled in the respective Find and Create commands
      sig { override.returns(Result) }
      def perform
        found_result = T.let(Find.call(
            owner:,
            spark_id:,
            repository_id:,
          ),
        Find::Result)
        log_info(action: "find_existing", spark_id: spark_id, workbench_cloudspace: found_result.workbench_cloudspace)
        if workbench_cloudspace = found_result.workbench_cloudspace
          result = Result.new(workbench_cloudspace)
          result.env = found_result.env if found_result.env.present?
          result.found = true

          @operation.mark_as_ended
          return result
        end

        create_result = T.let(Create.call(
            owner:,
            spark_id:,
            repository_id:,
            template_repository_id:,
            operation:,
            sku_name:,
            vscs_target:,
            vscs_target_url:
          ),
        Create::Result)
        log_info(action: "create_new", spark_id: spark_id, workbench_cloudspace: create_result.workbench_cloudspace)
        result = Result.new(create_result.workbench_cloudspace)
        result.env = create_result.env if create_result.env.present?
        result.found = false

        result
      end

      def log_info(action:, spark_id:, workbench_cloudspace:)
        GitHub.logger.info(
          "code.namespace": "Workbench::SparkCloudspaces::FindOrCreate",
          "spark_id": spark_id,
          "repository_id": repository_id,
          "template_repository_id": template_repository_id,
          "action": action,
          "cloudspace_found": workbench_cloudspace&.cloud_environment.present?,
          "cloudspace_guid": workbench_cloudspace&.cloud_environment&.guid,
          "state": workbench_cloudspace&.cloud_environment&.state,
        )
      end
    end
  end
end
