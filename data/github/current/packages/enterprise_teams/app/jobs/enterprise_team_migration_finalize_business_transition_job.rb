# typed: true
# frozen_string_literal: true

class EnterpriseTeamMigrationFinalizeBusinessTransitionJob < ApplicationJob
  queue_as :enterprise_team_migration
  retry_on_dirty_exit

  sig { params(business_id: Integer).void }
  def perform(business_id:)
    business = Business.find_by(id: business_id)
    return if business.nil?

    with_write do
      business.with_lock do
        return unless business.seats_plan_basic?
        return if business.enterprise_teams.exists?

        unless business.transition_to_seats_plan_type(:full)
          raise "EnterpriseTeamMigrationFinalizeBusinessTransitionJob failed to transition Business #{business.id} to full seats plan"
        end
      end
    end

    BusinessMailer.enterprise_team_migration_completed(business).deliver_later

    customer_id = business.customer_id
    if customer_id
      Licensing::SyncCustomerLicensesInLicensifyJob.perform_later(customer_id)
    end
  end
end
