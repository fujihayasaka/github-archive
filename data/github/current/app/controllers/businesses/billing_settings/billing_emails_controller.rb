# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::BillingEmailsController < Businesses::BusinessController
  before_action :ensure_billing_enabled
  before_action :business_access_required

  def create
    email = params[:billing_external_email]
    errors = this_business.add_billing_email(email)
    if errors.any?
      flash[:error] = errors.to_sentence
    else
      flash[:notice] = "Email #{email} added as a billing recipient."
    end

    if this_business.billed_via_billing_platform?
      redirect_to enterprise_billing_contacts_path(this_business)
    else
      redirect_to settings_billing_tab_enterprise_path(this_business, tab: :billing_emails)
    end
  end

  def destroy
    begin
      email = this_business.billing_external_emails.find(params[:id])
      if email.destroy
        flash[:notice] = "Successfully removed email from billing recipients."
      else
        flash[:error] = email.errors.full_messages.to_sentence
      end
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "Email not found."
    end

    if this_business.billed_via_billing_platform?
      redirect_to enterprise_billing_contacts_path(this_business)
    else
      redirect_to settings_billing_tab_enterprise_path(this_business, tab: :billing_emails)
    end
  end

  def mark_primary # rubocop:todo GitHub/UseRestfulActions
    email = this_business.billing_external_emails.find(params[:id])
    errors = this_business.mark_billing_email_primary(email)
    if errors.any?
      flash[:error] = errors.to_sentence
    else
      flash[:notice] = "Successfully marked email as primary recipient."
    end

    if this_business.billed_via_billing_platform?
      redirect_to enterprise_billing_contacts_path(this_business)
    else
      redirect_to settings_billing_tab_enterprise_path(this_business, tab: :billing_emails)
    end
  end

  def update_primary # rubocop:todo GitHub/UseRestfulActions
    email = params[:business][:billing_email]
    this_business.billing_email = email
    if this_business.save
      flash[:notice] = "Successfully updated billing email for #{this_business.name}."
    else
      flash[:error] = this_business.errors.full_messages.to_sentence
    end

    if this_business.billed_via_billing_platform?
      redirect_to enterprise_billing_contacts_path(this_business)
    else
      redirect_to settings_billing_tab_enterprise_path(this_business, tab: :billing_emails)
    end
  end
end
