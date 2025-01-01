# typed: strict
# frozen_string_literal: true

class Orgs::BillingSettings::BillingInformationLinkingController < ApplicationController
  include OrganizationsHelper
  include TradeControlsControllerMethods

  before_action :login_required
  before_action :org_billing_management_only
  before_action :ensure_billing_enabled
  before_action :ensure_has_target

  sig { void }
  def update
    link_trade_screening_record_to_org
  end

  private

  sig { void }
  def ensure_has_target
    render_404 unless current_organization_for_member_or_billing
  end
end
