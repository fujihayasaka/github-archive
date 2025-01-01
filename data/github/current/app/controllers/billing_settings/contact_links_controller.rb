# typed: strict
# frozen_string_literal: true

# This controller is for the creating and updating of links between billing contacts
#   and orgs on the standard terms of service.
class BillingSettings::ContactLinksController < ApplicationController

  include Contacts::SharedControllerMethods
  include TradeControlsControllerMethods

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_reading_billing_contact_enabled
  before_action :ensure_adminable
  before_action :ensure_user_billing_contact_exists, only: [:create]

  sig { void }
  def create
    if org.link_billing_contact(actor: current_user)
      flash[:success] = "Billing information successfully linked to #{org.display_login}"
    else
      flash[:error] = "An error occurred while linking billing information."
    end

    redirect_back(fallback_location: billing_path(target))
  end

  sig { void }
  def destroy
    if org.unlink_billing_contact(actor: current_user)
      flash[:success] = "Billing information successfully removed from #{org.display_login}"
    else
      flash[:error] = "An error occurred while removing billing information."
    end

    redirect_back(fallback_location: billing_path(target))
  end

  private

  sig { void }
  def ensure_target
    return render_404 if target.nil?
    render_404 unless target&.org_is_on_standard_tos?
  end

  sig { void }
  def ensure_adminable
    render_404 unless org.adminable_by?(current_user) || org.billing_manager?(current_user)
  end

  sig { void }
  def ensure_user_billing_contact_exists
    render_404 unless current_user.billing_contact.persisted?
  end

  sig { returns(Organization) }
  memoize def org
    T.cast(target, Organization)
  end
end
