# typed: true
# frozen_string_literal: true

module Octoshift
  class OrganizationMigration
    include GitHub::Relay::GlobalIdentification
    extend Forwardable

    def_delegators :@org_migration, :id, :source_org_name, :target_org_name, :source_org_url, :target_enterprise_id, :failure_reason

    def_delegator :@org_migration, :migration_state, :state
    def_delegator :@org_migration, :id, :database_id

    def initialize(org_migration)
      @org_migration = org_migration
    end

    def platform_type_name
      "OrganizationMigration"
    end

    def async_enterprise
      Platform::Loaders::ActiveRecord.load(::Business, target_enterprise_id)
    end

    def created_at
      @org_migration.created_at.to_time
    end

    def total_repositories_count
      @org_migration.total_repositories_count.value || 0
    end

    def remaining_repositories_count
      @org_migration.remaining_repositories_count.value || 0
    end
  end
end
