# typed: true
# frozen_string_literal: true

class Azure::BaseController < ApplicationController
  include Azure::SubscriptionsDependency

  before_action :login_required,
    :ensure_billing_enabled

  private

  def org_billing_settings_path(anchor: nil)
    if target.billed_via_billing_platform?
      settings_org_billing_tab_path(organization_id: target.display_login, tab: "payment_information", anchor: anchor)
    else
      settings_org_billing_path(target, anchor: anchor)
    end
  end

  def org_billing_settings_url
    if target.billed_via_billing_platform?
      settings_org_billing_tab_url(organization_id: target.display_login, tab: "payment_information")
    else
      settings_org_billing_url(target)
    end
  end

  def target_for_conditional_access # rubocop:todo GitHub/UseRestfulActions
    # CAP is not needed if there is no target. We'd 404 in that case.
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  memoize def target # rubocop:todo GitHub/UseRestfulActions
    current_user&.organizations&.find_by_login!(params[:account_id])
  end
end
