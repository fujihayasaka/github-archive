# typed: strict
# frozen_string_literal: true

class Copilot::BatchInvalidateAccessTypeCacheJob < CopilotJob
  queue_as :copilot_update_org_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  gate_with_feature_flag :copilot_batch_invalidate_access_type_cache_job

  resolve_tenant_context do |owner_type, owner_id|
    case owner_type
    when "Business"
      ::Business.find_by(id: owner_id)
    when "Organization"
      ::Organization.find_by(id: owner_id)&.business
    end
  end

  BATCH_SIZE = 1_000

  sig { params(owner_type: String, owner_id: Integer, reason: String).void }
  def perform(owner_type, owner_id, reason)
    case owner_type
    when "Business"
      business = ::Business.find_by(id: owner_id)
      return if business.nil?

      invalidate_for_business(business, reason)
    when "Organization"
      org = ::Organization.find_by(id: owner_id)
      return if org.nil?

      invalidate_for_organization(org, reason)
    end
  end

  private

  sig { params(business: ::Business, reason: String).void }
  def invalidate_for_business(business, reason)
    GitHub.logger.with_named_tags("gh.business.id" => business.id) do
      count = 0
      Copilot::Seat.all_active_seats_in_business(business)
        .includes(:assigned_user)
        .find_in_batches(batch_size: BATCH_SIZE) do |batch|
          users = batch.filter_map(&:assigned_user)
          next if users.empty?

          Copilot::Cache::SeatsCheckClient.new(user: users).invalidate(reason)
          Copilot::Cache::SeatAssignmentsRevokedCheckClient.new(user: users).invalidate(reason)
          count += users.size
        end
      GitHub.logger.info("Invalidated seats check and seat assignments revoked cache for #{count} seats in business #{business.id}, reason: #{reason}")
    end
  end

  sig { params(org: ::Organization, reason: String).void }
  def invalidate_for_organization(org, reason)
    GitHub.logger.with_named_tags("gh.org.id" => org.id) do
      count = 0
      Copilot::Seat.where(organization_id: org.id)
        .includes(:assigned_user)
        .find_in_batches(batch_size: BATCH_SIZE) do |batch|
          users = batch.filter_map(&:assigned_user)
          next if users.empty?

          Copilot::Cache::SeatsCheckClient.new(user: users).invalidate(reason)
          Copilot::Cache::SeatAssignmentsRevokedCheckClient.new(user: users).invalidate(reason)
          count += users.size
        end
      GitHub.logger.info("Invalidated seats check and seat assignments revoked cache for #{count} seats in org #{org.id}, reason: #{reason}")
    end
  end
end
