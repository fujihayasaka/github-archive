# typed: true
# frozen_string_literal: true

class BusinessBulkAddMembersToOrganizationsJob < ApplicationJob
  queue_as :business_bulk_action

  retry_on_dirty_exit

  BATCH_SIZE = 100

  resolve_tenant_context do |business|
    business
  end

  def perform(business, actor, organization_ids, user_ids)
    user_ids = user_ids.map(&:to_i)
    ActiveRecord::Base.connected_to(role: :reading) do
      users = allowed_users(business, actor, user_ids)
      business.organizations.where(id: organization_ids).find_each(batch_size: BATCH_SIZE) do |org|
        next unless org.adminable_by?(actor)
        ActiveRecord::Base.connected_to(role: :writing) do
          users.each do |user|
            org.add_member(user, adder: actor)
          end
        end
      end
    end
  end

  private

  def allowed_users(business, actor, user_ids)
    if business.enterprise_managed_user_enabled?
      User.joins(:external_identities).
        where(
          id: user_ids,
          external_identities: {
            provider_id: business.external_provider.id,
            provider_type: business.external_provider.class.name,
            disabled_at: nil
        })
    else
      User.where(id: (user_ids & allowed_user_ids(business, actor)))
    end
  end

  def allowed_user_ids(business, actor)
    if GitHub.single_business_environment?
      business.filtered_members(actor).pluck(:id)
    else
      business.filtered_members(actor).includes(:user).map { |account| account&.user&.id }.compact
    end
  end
end
