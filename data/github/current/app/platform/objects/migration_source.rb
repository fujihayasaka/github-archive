# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MigrationSource < Platform::Objects::Base
      description "A GitHub Enterprise Importer (GEI) migration source."

      # This ready date is here for ceremony only. Since this is behind the :import_api
      # and no usage this has been made to use the new format for all objects.
      implements_node templates: [
        [:ms, :id],
        [:ms_staging, :id],
        [:ms_review_lab, :id],
        [:ms_load_testing, :id]
      ], as: "MS", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |connector|
        Loaders::ActiveRecord.load(::User, connector.owner_id).then do |owner|
          # login is fine for comparison purposes
          prefix = if T.must(owner).login == "octoshift-review-lab" # rubocop:disable GitHub/DoNotAllowLogin
            :ms_review_lab
          elsif T.must(owner).login == "octoshift-load-testing" # rubocop:disable GitHub/DoNotAllowLogin
            :ms_load_testing
          elsif ::FeatureFlag.vexi.enabled_or_raise?(:octoshift_use_staging, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            :ms_staging
          else
            :ms
          end

          { prefix: prefix, id: connector.id }
        end
      end

      scopeless_tokens_as_minimum

      field :name, String, "The migration source name.", null: false
      field :url, Scalars::URI, description: "The migration source URL, for example `https://github.com` or `https://monalisa.ghe.com`.", null: false
      field :type, Enums::MigrationSourceType, description: "The migration source type.", null: false

      attr_accessor :owner

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, migration_source)
        migration_source.async_owner.then do |owner|
          owner.async_business.then do
            permission.access_allowed?(
              :octoshift_import,
              resource: owner,
              organization: owner,
              current_repo: nil
            )
          end
          @owner = owner
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_owner.then do |owner|
          owner.async_business.then do
            permission.access_allowed?(
                :octoshift_import,
                resource: owner,
                organization: owner,
                current_repo: nil
            )
          end
          @owner = owner
        end
      end

      def self.load_from_next_global_id(parsed_id)
        use_staging = parsed_id.parts[:prefix].to_sym == :ms_staging
        use_review_lab = parsed_id.parts[:prefix].to_sym == :ms_review_lab
        use_load_testing = parsed_id.parts[:prefix].to_sym == :ms_load_testing
        load_migration_source(parsed_id.id, use_staging: use_staging, use_review_lab: use_review_lab, use_load_testing: use_load_testing)
      end

      def self.load_from_global_id(id)
        load_migration_source(id)
      end

      def self.load_migration_source(id, use_staging: false, use_review_lab: false, use_load_testing: false)
        connection_builder = if use_staging
          Octoshift::Twirp::ConnectionBuilder.staging
        elsif use_review_lab
          Octoshift::Twirp::ConnectionBuilder.review_lab
        elsif use_load_testing
          Octoshift::Twirp::ConnectionBuilder.load_testing
        else
          Octoshift::Twirp::ConnectionBuilder.new
        end

        connector_client = Octoshift::Twirp::ConnectorClient.new(faraday_connection: connection_builder.build)
        connector = connector_client.get_connector(connector_id: id)

        Octoshift::MigrationSource.new(connector)
      rescue Faraday::ConnectionFailed, Errno::ECONNRESET
        Octoshift::DatadogHelper.send_service_unavailable_stats(@owner)
        raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
      rescue Octoshift::Twirp::ConnectorNotFound => e
        raise(Errors::NotFound, "Migration source not found with ID #{id}.")
      end
    end
  end
end
