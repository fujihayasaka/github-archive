# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BusinessUserAccountUpdateUserJob < ApplicationJob
  queue_as :business_user_account_update_user

  retry_on_dirty_exit

  resolve_tenant_context do |business|
    business
  end

  # Public: Background job wrapper for BusinessUserAccount#update_user
  #
  # business - Business to which the user accounts belong to.
  # user_account_ids - Optional Array of Integer representing the IDs of BusinessUserAccount to be updated.
  def perform(business, user_account_ids: nil)
    business_user_accounts(business, user_account_ids).each do |bua|
      bua.update_user
      if bua.changed?
        with_write { bua.save! }
      end
    end
    BusinessUserAccountUpdateAttributesJob.enqueue(business, user_account_ids: user_account_ids)
  end

  def business_user_accounts(business, ids)
    if ids.nil?
      business.user_accounts
    else
      business.user_accounts.where(id: ids)
    end
  end
end
