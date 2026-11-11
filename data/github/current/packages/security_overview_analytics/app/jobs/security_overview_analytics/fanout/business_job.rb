# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    class BusinessJob < TenantBaseJob

      queue_as :security_overview_analytics_tenant_fanout

      sig do
        params(
          args: T.untyped,
          offset_item_id: Integer,
          kwargs: T.untyped,
        )
        .returns(T::Array[Integer])
      end
      def next_batch(*args, offset_item_id:, **kwargs)
        repo_owner_type = T.must(owner_type)
        business = T.cast(tenant, ::Business)
        case repo_owner_type
        when Types::Owner::Organization
          business
            .organizations
            .where(::Organization.arel_table[:id].gt(offset_item_id))
            .order(:id)
            .limit(BATCH_SIZE)
            .pluck(:id)
        when Types::Owner::User
          advanced_security = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business)
          return [] unless advanced_security.feature_available_for_user_repositories?
          advanced_security.list_enterprise_users_offset(offset_id: offset_item_id, per_page: BATCH_SIZE).pluck(:id)
        else
          T.absurd(repo_owner_type)
        end
      end

      sig do
        params(
          repository_owner_ids: T::Array[Integer],
          args: T.untyped,
          kwargs: T.untyped,
        )
        .void
      end
      def process_batch(repository_owner_ids, *args, **kwargs)
        repo_owner_type = T.must(owner_type)
        fanout_tenant_scope = if repo_owner_type == Types::Owner::Organization
          Types::TenantScope::Organization.serialize
        elsif repo_owner_type == Types::Owner::User
          Types::TenantScope::User.serialize
        else
          T.absurd(repo_owner_type)
        end

        repository_owner_ids.each do |owner_id|
          fanout_jobs.each do |job|
            job.perform_later(
              tenant_scope: fanout_tenant_scope,
              tenant_id: owner_id,
              action: action&.serialize,
              features: features.map { |feature| feature&.serialize }.compact
            )
          end
        end
      end

      protected

      sig { override.returns(T::Array[Types::TenantScope]) }
      def allowed_tenant_scopes
        [Types::TenantScope::Business]
      end

      sig { override.returns(T::Boolean) }
      def should_perform?
        return false unless super

        business = T.cast(tenant, ::Business)
        support_user_owner = business.enterprise_managed? || GitHub.enterprise?
        unless owner_type != Types::Owner::User || support_user_owner
          log_fanout_stopped(:user_owner_not_supported)
          return false
        end

        true
      end
    end
  end
end
