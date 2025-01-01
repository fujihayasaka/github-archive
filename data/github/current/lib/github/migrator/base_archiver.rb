# typed: true
# frozen_string_literal: true

module GitHub
  class Migrator
    class BaseArchiver
      include DownloadHelpers

      def initialize(options = {})
        @actor          = options[:actor]
        @migration_path = options[:migration_path]
      end

      # Public: Actor for asset policies.
      #
      # Returns a User.
      attr_reader :actor

      # Public: Path to store migration files at.
      #
      # Returns a Pathname
      attr_reader :migration_path

      private

      def asset_namespace
        raise "Define in subclass"
      end

      def logger_fn
        raise "Define in subclass"
      end

      def path_segment(asset)
        asset.guid
      end

      def save_asset(asset)
        destination_path = File.join(migration_path, asset_namespace, path_segment(asset), asset.name)
        FileUtils.mkdir_p(File.dirname(destination_path))

        policy = asset.storage_policy(actor: actor)
        ok, http_status = save_from_url(url: policy.download_url, to: destination_path)

        if !ok
          GitHub.logger.info(
            {
              "code.function" => logger_fn,
              "gh.migration_tools.migration.type" => "repo",
              "gh.migration_tools.migration.asset.storage" => asset_storage_type,
              "gh.migration_tools.migration.asset.type" => asset.class.base_class.name,
              "gh.migration_tools.migration.asset.id" => asset.id,
              "http.status_code" => http_status
            }
          )
        end
      end

      def asset_storage_type
        if GitHub.storage_cluster_enabled?
          "cluster"
        elsif GitHub.s3_uploads_enabled?
          "s3"
        end
      end
    end
  end
end
