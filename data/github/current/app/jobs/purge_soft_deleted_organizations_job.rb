# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class PurgeSoftDeletedOrganizationsJob < ApplicationJob
  queue_as :purge_soft_deleted_organizations
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 30.minutes

  exempt_from_tenant_context_requirement

  PURGEABLE_ORG_LIMIT = 100

  def perform
    actor = User.ghost

    Organization.purgeable.limit(PURGEABLE_ORG_LIMIT).find_each do |organization|
      with_write do
        begin
          organization.skip_admins_presence_validation = true
          organization.async_destroy(actor)
        rescue ActiveRecord::RecordInvalid => error
          # Report and continue
          Failbot.report(error)
        end
      end
    end
  end
end
