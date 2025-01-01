# typed: true
# frozen_string_literal: true

class Billing::Settings::LfsBillingBannerComponent < ApplicationComponent
  extend T::Sig

  sig { params(account: T.any(User, Organization, Business), dismissible: T::Boolean).void }
  def initialize(account:, dismissible: false)
    @account = account
    @dismissible = dismissible
  end

  private

  attr_reader :account, :dismissible

  sig { returns(T::Boolean) }
  def render?
    return false if !GitHub.billing_enabled?
    return false if !account.feature_enabled?(:lfs_billing_changes_banner)
    return false if !account.present?
    return false if !logged_in?
    return false if !account.is_a?(Business) && (account&.personal_plan? || account&.org_free_plan?)
    if account.business?
      aggregated_asset_status = account.aggregated_asset_status
      return true if aggregated_asset_status[:bandwidth_usage] > 0 || aggregated_asset_status[:storage_usage] > 0 || aggregated_asset_status[:asset_packs] > 0
    end

    false
  end
end
