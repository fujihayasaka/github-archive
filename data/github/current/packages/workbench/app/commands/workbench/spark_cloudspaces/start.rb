# typed: true
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    class Start < CloudEnvironments::Command

      class Result
        include GitHub::Memoizer

        sig { params(workbench_cloudspace: Workbench::Cloudspace).returns(Workbench::Cloudspace) }
        attr_writer :workbench_cloudspace

        sig { params(env: Codespaces::Environment).returns(Codespaces::Environment) }
        attr_writer :env

        sig { returns(T.nilable(Workbench::Cloudspace)) }
        attr_reader :workbench_cloudspace

        sig { returns(T.nilable(Codespaces::Environment)) }
        attr_reader :env
      end

      include ActiveModel::Validations

      attr_reader :owner, :cloudspace_guid, :repository_id, :cap_filter, :result, :operation, :entry_point

      sig do
        params(
          owner: ::User,
          cloudspace_guid: String,
          repository_id: Integer,
          cap_filter: ConditionalAccess::Web::Filter,
          operation: Codespaces::AsyncOperation,
          entry_point: T.nilable(String),
        ).void
      end
      def initialize(
          owner:,
          cloudspace_guid:,
          repository_id:,
          cap_filter:,
          operation:,
          entry_point: nil
        )
        @owner = owner
        @cloudspace_guid = cloudspace_guid
        @repository_id = repository_id
        @cap_filter = cap_filter
        @operation = operation
        @result = Result.new
        @entry_point = entry_point
      end

      sig { override.returns(Result) }
      def perform
        validate!

        @result.workbench_cloudspace = Workbench::Cloudspace.new(cloud_environment)
        unless cloud_environment&.suspended?
          # Just return the environment info if its not suspended
          @result.env = cloud_environment&.environment_data
          return @result
        end

        if Codespaces::Policy.codespace_user_spammy?(cloud_environment)
          operation.mark_as_ended
          raise StandardError, "Forbidden: User is not allowed to perform this operation"
        end

        extra_secrets = []

        workbench = ::Spark::Workbench.for_cloud_environment_id(cloud_environment.id)

        if workbench.present?
          if workbench.runtime_app.present?
            extra_secrets << {
              "type" => Codespaces::Secret::TYPE_ENV_VAR,
              "name" => "GITHUB_RUNTIME_PERMANENT_NAME",
              "value" => workbench.runtime_app&.permanent_name,
            }
          end

          # We pass in this sas uri for resume from blob.
          if owner&.feature_flag_enabled?(:workspace_resume_from_blob, default: false)
            if (sas_uri = Workbench::SnapshotBlobs.get_snapshot_upload_uri(workbench.uuid_string, current_user: owner))
              extra_secrets << {
                "type" => Codespaces::Secret::TYPE_ENV_VAR,
                "name" => "SNAPSHOT_SAS_URL",
                "value" => sas_uri,
              }
            end
          end

          extra_secrets << {
              "type" => Codespaces::Secret::TYPE_ENV_VAR,
              "name" => "SPARK_WORKBENCH_ID",
              "value" => workbench.uuid_string,
            }
        end

        result = begin
          Codespaces::Start.call(
            cloud_environment,
            user: owner,
            cap_filter:,
            entry_point:,
            operation:,
            extra_secrets: extra_secrets,
          )
        rescue => e # rubocop:disable Lint/RescueException
          operation.mark_as_failed(failure_reason: e)
          raise
        end

        env = fetch_environment!
        if env.present?
          @result.env = env
        elsif cloud_environment.environment_data.present?
          @result.env = cloud_environment.environment_data
        end

        @result
      end

      private

      memoize def cloud_environment
        return unless cloudspace_guid

        # Look at ephemeral cloud environments for backwards compatibility
        owner.codespaces.visible_to_workbench_cloud_environments(owner).find_by(guid: cloudspace_guid) ||
          owner.codespaces.visible_to_ephemeral_cloud_environments(owner).find_by(guid: cloudspace_guid)
      end

      def fetch_environment!
        return unless cloud_environment&.guid
        Codespaces::VscsClient.for_codespace(cloud_environment).fetch_environment!(cloud_environment.guid)
      rescue Codespaces::Client::BadResponseError => e
        # If there is an error fetching from the service we will just ignore it and return the cached data.
        # Client side polling will eventually get the connection data.
        nil
      end
    end
  end
end
