# typed: true
# frozen_string_literal: true

class BusinessUserAccountCreateForOrganizationJob < ApplicationJob
  queue_as :business_user_accounts

  retry_on_dirty_exit

  BATCH_SIZE = 1_000

  resolve_tenant_context do |business|
    business
  end

  # Public: Background job wrapper for Business#add_user_accounts
  #
  # business - Business to which members are being added.
  # organization - The Organization whose users are being added.
  def perform(business, organization)
    user_ids = Organization::LicenseAttributer.new(organization).user_ids.to_a
    with_write do
      user_ids.in_groups_of(BATCH_SIZE, false) do |slice|
        # In GHES the users will already be members, so just update their account attributes instead.
        if GitHub.single_business_environment?
          user_account_ids = BusinessUserAccount.where(business_id: business.id, user_id: slice).pluck(:id)
          BusinessUserAccountUpdateAttributesJob.perform_later(business, user_account_ids: user_account_ids)
        else
          business.add_user_accounts slice, business_roles_bitfield: BusinessUserAccount.roles_bitmask([:member])
        end
      end
    end
    business.update_license_usage
  end
end
