# typed: true
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    class FindOrCreate < CloudEnvironments::Command
      NAMESPACE = "Workbench::SparkCloudspaces::FindOrCreate"

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

      attr_reader :owner, :repository_id, :template_repository_id, :spark_id, :devcontainer_path, :sku_name, :vscs_target, :vscs_target_url, :result, :operation, :branch_name

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
          template_repository_id: T.nilable(Integer),
          branch_name: T.nilable(String)
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
          template_repository_id: nil,
          branch_name: nil
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
        @branch_name = branch_name
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

        should_resume_from_blob = false

        spark = Spark::Workbench.for_uuid_string(owner&.id, spark_id)
        workbench_cloudspace = found_result.workbench_cloudspace

        if owner&.feature_flag_enabled?(:spark_enable_ephemeral_codespaces, default: false)
          snapshotted = spark&.last_snapshot_environment_id == spark&.cloud_environment_id
        else
          snapshotted = spark&.last_snapshot_environment_id == workbench_cloudspace&.cloud_environment&.id
        end

        if owner&.feature_flag_enabled?(:workspace_resume_from_blob, default: false) && snapshotted
          should_resume_from_blob = true
        end

        # If we aren't properly snapshotted, we'll try to resume.
        # If we do then we might be in a bad state that we need to correct on Sparks
        # with exported repos before we stopped associating user repos to the Codespace record.
        if !snapshotted
          maybe_fix_user_repo_oid_mismatch(workbench_cloudspace)
        end

        log_info(action: "find_existing", spark_id: spark_id, workbench_cloudspace: workbench_cloudspace)

        # if cloud env id is already set and codespace was deleted or state is shutdown then its a resume
        if spark&.cloud_environment_id.present? && (!workbench_cloudspace || found_result.env&.suspended?)
          GitHub.logger.info(
            "code.namespace": NAMESPACE,
            "action": "resume_from_blob",
            "spark_id": spark_id,
            "snapshotted": snapshotted,
            "resume_from_blob": should_resume_from_blob,
            "cloudspace_found": !!workbench_cloudspace&.cloud_environment,
            "cloudspace_guid": workbench_cloudspace&.cloud_environment&.guid,
            "state": workbench_cloudspace&.cloud_environment&.state,
            "resume_from_blob_enabled": owner&.feature_flag_enabled?(:workspace_resume_from_blob, default: false)
          )
        end

        # If we have an existing codespace and the last snapshot was unsuccessful, return it to initiate a resume
        if !should_resume_from_blob && workbench_cloudspace
          if owner&.feature_flag_enabled?(:spark_add_repo_permission_on_resume, default: false) && spark&.repository_id
            add_repo_permission(spark:, workbench_cloudspace:)
          end
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
            vscs_target_url:,
            branch_name:
          ),
        Create::Result)

        workbench_cloudspace = create_result.workbench_cloudspace
        log_info(action: "create_new", spark_id: spark_id, workbench_cloudspace: workbench_cloudspace)

        if workbench_cloudspace.present? && spark&.repository_id.present?
          add_repo_permission(spark:, workbench_cloudspace:)
        end

        result = Result.new(workbench_cloudspace)
        result.env = create_result.env if create_result.env.present?
        result.found = false

        result
      end

      def log_info(action:, spark_id:, workbench_cloudspace:)
        GitHub.logger.info(
          "code.namespace": NAMESPACE,
          "spark_id": spark_id,
          "repository_id": repository_id,
          "template_repository_id": template_repository_id,
          "action": action,
          "cloudspace_found": workbench_cloudspace&.cloud_environment.present?,
          "cloudspace_guid": workbench_cloudspace&.cloud_environment&.guid,
          "state": workbench_cloudspace&.cloud_environment&.state,
        )
      end

      # Fix for Codespaces in situation reported in https://github.com/github/spark/issues/1899.
      #
      # In these cases, we were assigning the Codespace repo on export to the user repo.
      # However, the oid was the one for spark-template which gets squashed out on the user repo.
      # We rarely hit the resume path here -- only when snapshotting has failed -- so this
      # doesn't happen often, but when it does this fix will allow the codespace to resume with
      # a proper oid.
      def maybe_fix_user_repo_oid_mismatch(workbench_cloudspace)
        # If we didn't find a Codespace, nothing to correct
        return unless workbench_cloudspace&.cloud_environment

        # If we're on the spark template repo, skip out early
        return if workbench_cloudspace.cloud_environment.repository.id == @template_repository_id

        # Need the full Codespace to fiddle with the oid. Sorry.
        cs = Codespace.find(workbench_cloudspace.cloud_environment.id)
        repo = T.must(cs.repository)

        needs_fix = false
        begin
          commit = Repositories.domain.commits.by_oid(
            repository: repo,
            commit_oid: cs.oid,
          )
        rescue GitRPC::ObjectMissing
          needs_fix = true
        end

        return unless needs_fix

        FixOid.fix_oid(cs)
      end

      def add_repo_permission(spark:, workbench_cloudspace:)
        published_repo_id = spark&.repository_id
        published_repo = T.cast(Repositories.domain.by_id(published_repo_id), T.nilable(Repository)) if published_repo_id # rubocop:todo GitHub/AvoidCast

        GitHub.logger.info(
          "code.namespace": NAMESPACE,
          "spark_id": spark_id,
          "spark_found": !!spark,
          "published_repo_id": published_repo&.id,
          "published_repo_found": !!published_repo,
          "message": "Check if published repo exists",
        )

        if published_repo
          codespace = Codespace.find_by(id: workbench_cloudspace.cloud_environment.id)
          GitHub.logger.info(
            "code.namespace": NAMESPACE,
            "spark_id": spark_id,
            "spark_found": !!spark,
            "codespace_id": codespace&.id,
            "codespace_found": !!codespace,
            "published_repo_id": published_repo.id,
            "message": "Start add repo permissions",
          )

          if codespace.present?
            installation_update_results = Codespace.active_installations_for([codespace.id]).map do |installation|
              SiteScopedIntegrationInstallation::Editors::Repository.grant(
                installation, repositories: [published_repo], entry_point: :codespaces_command_publish_to_repository
              )
            end

            if installation_update_results.any?(&:failed?)
              GitHub.logger.error(
                "code.namespace": NAMESPACE,
                "error": "Failed to grant repository access: #{installation_update_results.first&.reason}",
                "codespace_id": codespace.id,
                "repository_id": published_repo.id
              )
            end
          end
        end
      end
    end
  end
end
