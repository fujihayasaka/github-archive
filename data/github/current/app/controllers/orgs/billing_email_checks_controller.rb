# typed: true
# frozen_string_literal: true

class Orgs::BillingEmailChecksController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods

  before_action :login_required
  after_action :customer_category_instrumentation

  def create
    return head 400 if billing_email.blank?

    # Fail early and give some feedback if the user tries to add an email that appears
    # either on the sanctioned list or on the disposable list.
    if billing_email_valid?
      respond_to do |format|
        format.html_fragment do
          head 200
        end
      end
    else
      respond_to do |format|
        format.html_fragment do
          render body: "Email is invalid", status: 422, content_type: "text/fragment+html"
        end
      end
    end
  end

  private

  def billing_email
    params[:value]
  end

  def billing_email_valid?
    billing_email =~ User::EMAIL_REGEX &&
    !::TradeControls::Domains.sanctioned_email?(billing_email) &&
    !UserEmail::DisposableEmailsDependency.disposable_email?(billing_email)
  end
end
