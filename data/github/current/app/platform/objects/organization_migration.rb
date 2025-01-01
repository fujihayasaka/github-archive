# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class OrganizationMigration < Platform::Objects::Base
      description "A GitHub Enterprise Importer (GEI) organization migration."

      minimum_accepted_scopes ["read:org"]

      field :source_org_url, Platform::Scalars::URI, "The URL of the source organization to migrate.", null: false

      field :target_org_name, String, "The name of the target organization.", null: false

      field :state, Enums::OrganizationMigrationState, description: "The migration state.", null: false

      field :source_org_name, String, "The name of the source organization to be migrated.", null: false

      field :failure_reason, String, "The reason the organization migration failed.", null: true

      field :database_id, String, "Identifies the primary key from the database.", null: true

      field :remaining_repositories_count, Integer, "The remaining amount of repos to be migrated.", null: true

      field :total_repositories_count, Integer, "The total amount of repositories to be migrated.", null: true

      created_at_field

      attr_reader :enterprise

      implements_node templates: [
        [:om, :id],
        [:om_staging, :id],
        [:om_review_lab, :id]
      ], as: "OM", ready_date: "1970-01-01" do |org_migration|
        Loaders::ActiveRecord.load(::Business, org_migration.target_enterprise_id).then do |enterprise|
          @enterprise = enterprise
          prefix = if T.must(enterprise).name == "Teenyverse"
            :om_review_lab
          elsif ::FeatureFlag.vexi.enabled_or_raise?(:octoshift_use_staging, enterprise) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            :om_staging
          else
            :om
          end

          { prefix: prefix, id: org_migration.id }
        end
      end

      def self.async_viewer_can_see?(permission, object)
        # Let site admins view all org migrations
        return true if permission.viewer&.site_admin?

        object.async_enterprise.then do |enterprise|
          enterprise.owner?(permission.viewer)
        end
      end

      def self.async_api_can_access?(permission, object)
        # Let site admins view all org migrations
        return true if permission.viewer&.site_admin?

        object.async_enterprise.then do |enterprise|
          enterprise.owner?(permission.viewer)
        end
      end

      def self.load_from_next_global_id(parsed_id)
        use_staging = parsed_id.parts[:prefix].to_sym == :om_staging
        use_review_lab = parsed_id.parts[:prefix].to_sym == :om_review_lab
        use_load_testing = parsed_id.parts[:prefix].to_sym == :om_load_testing
        self.load_from_global_id(parsed_id.id, use_staging: use_staging, use_review_lab: use_review_lab, use_load_testing: use_load_testing)
      end

      def self.load_from_global_id(org_migration_id, use_staging: false, use_review_lab: false, use_load_testing: false)
        connection_builder = if use_staging
          Octoshift::Twirp::ConnectionBuilder.staging
        elsif use_review_lab
          Octoshift::Twirp::ConnectionBuilder.review_lab
        elsif use_load_testing
          Octoshift::Twirp::ConnectionBuilder.load_testing
        else
          Octoshift::Twirp::ConnectionBuilder.new
        end

        migration_client = Octoshift::Twirp::OrganizationMigrationClient.new(faraday_connection: connection_builder.build)
        migration_response = migration_client.get_org_migration(org_migration_id: org_migration_id)

        Octoshift::OrganizationMigration.new(migration_response)
      rescue Faraday::ConnectionFailed, Errno::ECONNRESET
        Octoshift::DatadogHelper.send_service_unavailable_stats(@enterprise)
        raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
      rescue Octoshift::Twirp::Error => e
        if e.message.include?("not found")
          raise Errors::NotFound.new("Organization Migration not found. This means that the ID you provided is invalid or the migration has been automatically deleted 7 days after it was created.")
        else
          raise Errors::Unprocessable.new(e.message)
        end
      end
    end
  end
end
