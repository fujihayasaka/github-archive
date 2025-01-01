# typed: strict
# frozen_string_literal: true

class Billing::Settings::ExtraBillingInfoModalComponent < ApplicationComponent
  sig { params(target: T.nilable(T.any(User, Organization))).void }
  def initialize(target:)
    @target = target
  end

  private

  sig { returns(T.nilable(T.any(User, Organization))) }
  attr_reader :target

  sig { returns(T::Boolean) }
  def render?
    GitHub.billing_enabled? && target.present? && logged_in?
  end

  sig { returns(String) }
  def form_path
    required_target = T.must(target)
    required_target.organization? ? org_extra_update_path(required_target) : billing_extra_update_path
  end

  sig { returns(String) }
  def payment_information_path
    required_target = T.must(target)
    if required_target.organization?
      settings_org_billing_tab_path(organization_id: required_target.display_login, tab: "payment_information")
    else
      settings_user_billing_tab_path(tab: "payment_information")
    end
  end

end
