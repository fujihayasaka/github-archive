# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class PreGhasSKUTrialEnabledRepository < ApplicationRecord::Domain::SecurityProductsEnablement
    validates :repository_id, presence: true
    validates :target_id, presence: true
    validates :target_type, presence: true
    validates :sku_name, presence: true

    BATCH_SIZE = T.let(1000, Integer)

    sig { params(billable_entity: T.untyped, sku_name: String).void }
    def self.capture_enabled_private_repos(billable_entity:, sku_name:)
      clear_old_records(billable_entity: billable_entity, sku_name: sku_name)

      enabled_repo_ids =  get_private_repo_ids_with_sku_enabled(billable_entity: billable_entity, sku_name: sku_name)
      records_to_insert = enabled_repo_ids.map do |repo_id|
        {
          target_id: billable_entity.id,
          target_type: billable_entity.class.name,
          repository_id: repo_id,
          sku_name: sku_name,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      records_to_insert.each_slice(BATCH_SIZE) do |batch|
        SecurityProductsEnablement::PreGhasSKUTrialEnabledRepository.insert_all(batch)
      end if records_to_insert.any?
    end

    sig { params(billable_entity: T.untyped, sku_name: String).returns(Integer) }
    def self.clear_old_records(billable_entity:, sku_name:)
      SecurityProductsEnablement::PreGhasSKUTrialEnabledRepository.where(
        target_id: billable_entity.id,
        target_type: billable_entity.class.name,
        sku_name: sku_name
      ).delete_all
    end

    # Get private repository IDs that have the specified SKU enabled for a given billing entity
    sig { params(billable_entity: T.untyped, sku_name: String).returns(T::Array[Integer]) }
    def self.get_private_repo_ids_with_sku_enabled(billable_entity:, sku_name:)
      repository_ids = case billable_entity
      when Organization
        billable_entity.org_repositories.where(public: false).pluck(:id)
      when Business
        # Get both organization repositories and user namespace repositories for EMU users
        repository_ids = []

        # Add organization repository IDs
        org_ids = billable_entity.organizations.pluck(:id)
        repository_ids.concat(::Repository.where(owner_id: org_ids, public: false).pluck(:id)) if org_ids.present?

        # Add user repository IDs for EMU users
        advanced_security_feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(billable_entity)

        if advanced_security_feature.feature_available_for_user_repositories?
          offset_id = T.let(0, Integer)

          while (user_ids = advanced_security_feature.list_enterprise_users_ids_offset(offset_id: offset_id, per_page: BATCH_SIZE)).present?
            repository_ids.concat(::Repository.where(owner_id: user_ids, public: false).pluck(:id))
            offset_id = user_ids.last
          end
        end

        repository_ids
      end

      # Use bulk query to find enabled repositories instead of N+1 queries
      get_enabled_repo_ids_from_batch(repository_ids.to_a, sku_name: sku_name)
    end


    # Check which repositories have the SKU enabled by querying feature status
    sig { params(repository_ids: T::Array[Integer], sku_name: String).returns(T::Array[Integer]) }
    def self.get_enabled_repo_ids_from_batch(repository_ids, sku_name:)
      return [] if repository_ids.empty?

      status_column = case sku_name
      when "code_security" then :code_scanning_alerts_status
      when "secret_protection" then :secret_scanning_alerts_status
      else return []
      end

      repository_ids.each_slice(BATCH_SIZE).flat_map do |batch_repo_ids|
        where_clause = { repository_id: batch_repo_ids }
        where_clause[status_column] = "ENABLED"
        SecurityOverviewAnalytics::FeatureStatus
          .where(**where_clause)
          .pluck(:repository_id)
      end
    end
  end
end
