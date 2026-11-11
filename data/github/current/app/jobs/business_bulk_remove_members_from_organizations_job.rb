# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessBulkRemoveMembersFromOrganizationsJob < ApplicationJob
  queue_as :business_bulk_action

  retry_on_dirty_exit

  BATCH_SIZE = 100

  resolve_tenant_context do |business|
    business
  end

  def perform(business, actor, organization_ids, user_ids)
    ActiveRecord::Base.connected_to(role: :reading) do
      users = allowed_users(business, actor, user_ids)
      business.organizations.where(id: organization_ids).find_each(batch_size: BATCH_SIZE) do |org|
        next unless org.adminable_by?(actor)
        ActiveRecord::Base.connected_to(role: :writing) do
          users.each do |user|
            next if org.adminable_by?(user)
            begin
              org.remove_member(user)
            rescue Organization::BusinessTeamsDependency::UnableToRemoveBusinessTeamMemberError
              # Don't let attempted removal of enterprise team members block removal of any other provided users.
              next
            end
          end
        end
      end
    end
  end

  def allowed_users(business, actor, user_ids)
    if business.enterprise_managed_user_enabled? && business.external_provider.present?
      User.joins(:external_identities).
        where(id: user_ids, external_identities: { provider_id: business.external_provider.id, provider_type: business.external_provider.class.name, active: true })
    else
      business.visible_organization_members_for(actor).where(id: user_ids)
    end
  end
end
