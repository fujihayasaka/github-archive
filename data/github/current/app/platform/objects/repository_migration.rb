# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoryMigration < Platform::Objects::Base
      description "A GitHub Enterprise Importer (GEI) repository migration."

      scopeless_tokens_as_minimum

      attr_reader :owner

      implements_node templates: [
        [:rm, :id],
        [:rm_staging, :id],
        [:rm_review_lab, :id],
        [:rm_load_testing, :id]
      ], as: "RM", ready_date: Platform::Helpers::GlobalId::COHORT_4 do |migration|
        owner_id = migration.migration_source.owner_id
        Loaders::ActiveRecord.load(::User, owner_id).then do |owner|
          @owner = owner
          # login is fine for comparison purposes
          prefix = if T.must(owner).login == "octoshift-review-lab" # rubocop:disable GitHub/DoNotAllowLogin
            :rm_review_lab
          elsif T.must(owner).login == "octoshift-load-testing" # rubocop:disable GitHub/DoNotAllowLogin
            :rm_load_testing
          elsif ::FeatureFlag.vexi.enabled_or_raise?(:octoshift_use_staging, owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            :rm_staging
          else
            :rm
          end

          { prefix: prefix, id: migration.id }
        end
      end

      implements Interfaces::Migration

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, migration)
        migration.async_migration_source.then do |migration_source|
          migration_source.async_owner.then do |owner|
            owner.async_business.then do
              permission.access_allowed?(
                :octoshift_import,
                resource: owner,
                organization: owner,
                current_repo: nil
              )
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_migration_source.then do |migration_source|
          migration_source.async_owner.then do |owner|
            owner.async_business.then do
              permission.access_allowed?(
                  :octoshift_import,
                  resource: owner,
                  organization: owner,
                  current_repo: nil
              )
            end
          end
        end
      end

      def self.load_from_next_global_id(parsed_id)
        use_staging = parsed_id.parts[:prefix].to_sym == :rm_staging
        use_review_lab = parsed_id.parts[:prefix].to_sym == :rm_review_lab
        use_load_testing = parsed_id.parts[:prefix].to_sym == :rm_load_testing
        Interfaces::Migration.load_from_global_id(parsed_id.id, use_staging: use_staging, use_review_lab: use_review_lab, use_load_testing: use_load_testing)
      rescue Faraday::ConnectionFailed, Errno::ECONNRESET
        Octoshift::DatadogHelper.send_service_unavailable_stats(@owner)
        raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
      end

      def self.load_from_global_id(migration_id)
        Interfaces::Migration.load_from_global_id(migration_id)
      rescue Faraday::ConnectionFailed, Errno::ECONNRESET
        Octoshift::DatadogHelper.send_service_unavailable_stats(@owner)
        raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
      end
    end
  end
end
