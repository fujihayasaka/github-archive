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
        business.add_user_accounts slice
      end
    end
    business.update_license_usage
  end
end
