# typed: true
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    class Find < CloudEnvironments::Command

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

      attr_reader :owner, :spark_id, :repository_id, :result

      sig do
        params(
          owner: ::User,
          spark_id: String,
          repository_id: Integer
        ).void
      end
      def initialize(
          owner:,
          spark_id:,
          repository_id:
        )
        @owner = owner
        @spark_id = spark_id
        @repository_id = repository_id
        @result = Result.new
      end

      sig { override.returns(Result) }
      def perform
        validate!

        if cloud_environment
          @result.workbench_cloudspace = Workbench::Cloudspace.new(cloud_environment)
          env = fetch_environment!
          if env.present? && !env.empty?
            @result.env = ::Codespaces::Environment.from_json(env)
          elsif cloud_environment.environment_data.present?
            @result.env = cloud_environment.environment_data
          end
        end

        # Force new creation if resuming from blob storage
        if owner&.feature_enabled?(:workspace_resume_from_blob)
          unless @result.env&.consuming_compute?
            @result = Result.new
          end
        end

        @result
      end

      private

      memoize def cloud_environment
        workbench = ::Workbench.load_workbench(owner.id, spark_id)
        cloudspace_id = workbench["cloudspace_id"] if workbench
        return unless cloudspace_id

        # Look at ephemeral cloud environments for backwards compatibility
        owner.codespaces.visible_to_workbench_cloud_environments(owner).find_by(id: cloudspace_id) ||
          owner.codespaces.visible_to_ephemeral_cloud_environments(owner).find_by(id: cloudspace_id)
      end

      def fetch_environment!
        return unless cloud_environment&.guid
        Codespaces::VscsClient.for_codespace(cloud_environment).fetch_environment!(cloud_environment.guid)
      rescue Codespaces::Client::BadResponseError => e
        # If there is an error fetching from the service we will just ignore it and return the cached data.
        # Client side polling will eventually get the connection data.
        nil
      end

      sig { returns(CloudEnvironments::IStatsTagger) }
      def stats_tagger
        @stats_tagger ||= Workbench::SparkCloudspaces::StatsTagger.new(
          location: cloud_environment&.location,
          repository: repository_id,
          spark_id: spark_id,
          sku_name: cloud_environment&.sku_name,
          owner: owner,
          use_prebuild: Codespaces::Prebuilds.configured?(cloud_environment&.repository),
          is_workbench_editor_cloud_environment: true,
        )
      end
    end
  end
end
