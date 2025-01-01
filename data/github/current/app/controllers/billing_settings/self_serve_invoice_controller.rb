# typed: true
# frozen_string_literal: true

class BillingSettings::SelfServeInvoiceController < ApplicationController
  include BillingSettingsHelper
  include OrganizationsHelper

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_target_is_billable
  before_action :ensure_target_billing_manageable

  def update
    enable_self_serve_invoicing = params[:send_invoice_with_receipt] == "true"

    if enable_self_serve_invoicing
      result = target.enable_self_serve_invoice(actor: current_user)
    else
      result = target.disable_self_serve_invoice(actor: current_user)
    end

    if result
      enabled_or_disabled = enable_self_serve_invoicing ? "enable" : "disable"
      GitHub.instrument("invoice_email_preference.#{enabled_or_disabled}", invoice_payload)
      flash[:notice] = "Successfully updated invoicing preference"
    else
      flash[:error] = "Something went wrong when updating invoice preferences. Please try again."
    end

    redirect_back(fallback_location: billing_path)
  end


  private

  def ensure_target
    render_404 if target.nil?
  end

  memoize def target
    target!
  end

  def target!
    if params[:organization_id]
      if site_admin?
        Organization.find_by_login(params[:organization_id])
      else
        org = current_organization_for_member_or_billing
        if org && org.billing_manageable_by?(current_user)
          org
        end
      end
    elsif params[:slug]
      Business.find_by(slug: params[:slug])
    elsif params[:user_id]
      if site_admin?
        User.find_by_login(params[:user_id])
      else
        current_user
      end
    end
  end

  def ensure_target_is_billable
    render_404 unless target.billable?
  end

  def ensure_target_billing_manageable
    render_404 unless target.adminable_by?(current_user) || (target.respond_to?(:billing_manager?) && target.billing_manager?(current_user)) || site_admin?
  end

  def billing_path(query_params = nil)
    target_billing_path(target, query_params)
  end

  private def invoice_payload
    payload = { actor: current_user }
    if target.is_a?(Business)
      payload.update(business: target)
    elsif target.is_a?(Organization)
      payload.update(org: target)
    else
      payload.update(user: target)
    end

    payload
  end
end
