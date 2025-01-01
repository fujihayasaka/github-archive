# typed: true
# frozen_string_literal: true

class PurgeSoftDeletedOrganizationsJob < ApplicationJob
  queue_as :purge_soft_deleted_organizations
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  schedule interval: 30.minutes

  exempt_from_tenant_context_requirement

  def perform
    actor = User.ghost

    Organization.purgeable.find_each do |organization|
      with_write do
        organization.skip_admins_presence_validation = true
        organization.async_destroy(actor)
      end
    end
  end
end
