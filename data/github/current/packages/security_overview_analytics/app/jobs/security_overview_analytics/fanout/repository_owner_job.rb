# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    class RepositoryOwnerJob < TenantBaseJob

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
        ::Repository
          .where(active: true, owner_id: tenant_id)
          .where(::Repository.arel_table[:id].gt(offset_item_id))
          .order(:id)
          .limit(BATCH_SIZE)
          .pluck(:id)
      end

      sig do
        params(
          repository_ids: T::Array[Integer],
          args: T.untyped,
          kwargs: T.untyped,
        )
        .void
      end
      def process_batch(repository_ids, *args, **kwargs)
        repository_ids.each do |id|
          fanout_jobs.each do |job|
            last_session_locked_at = last_session_locked_at(job)
            job.perform_later(repository_id: id, last_session_locked_at:)
          end
        end
      end

      protected

      sig { override.returns(T::Array[Types::TenantScope]) }
      def allowed_tenant_scopes
        [Types::TenantScope::Organization, Types::TenantScope::User]
      end

      sig { override.returns(T::Boolean) }
      def should_perform?
        return false unless super

        unless TenantValidationHelper.is_owner_in_scope?(T.cast(tenant, T.any(::Organization, ::User)))
          log_fanout_stopped(:owner_not_in_scope)
          return false
        end

        true
      end
    end
  end
end
