# typed: strict
# frozen_string_literal: true

# This controller is for the creating and updating of customer contact information
class BillingSettings::ContactsController < ApplicationController
  include Contacts::SharedControllerMethods

  before_action :ensure_billing_enabled
  before_action :login_required
  before_action :ensure_target
  before_action :ensure_target_billing_contact_exists, only: [:destroy]
  before_action :log_unpermitted_billing_params, only: [:create]

  # Create a new contact information record from parameters
  # This would also include tos changes
  sig { void }
  def create
    result = update_billing_contact
    report_status(action: T.must(__method__), success: result)
  end

  sig { void }
  def destroy
    if T.must(target).remove_billing_information(actor: current_user)
      flash[:notice] = "Successfully removed billing information."
      report_status(action: T.must(__method__), success: true)
    else
      flash[:error] = "Unable to remove billing information."
      log_contact_error(action: T.must(__method__), errors: ["Unable to remove billing information."])
    end

    redirect_back(fallback_location: billing_path(target))
  end

  private

  sig { void }
  def ensure_target
    render_404 if target.nil?
  end

  sig { void }
  def ensure_target_billing_contact_exists
    render_404 unless T.must(target).billing_contact.persisted?
  end

  # Logs request context when unpermitted params are found in billing_contact,
  # to help diagnose whether they originate from browser autofill, API clients, etc.
  sig { void }
  def log_unpermitted_billing_params
    return unless params[:billing_contact]

    submitted_keys = params[:billing_contact].keys
    extra_keys = submitted_keys - Contacts::SharedControllerMethods::PERMITTED_BILLING_CONTACT_KEYS

    return if extra_keys.empty?

    GitHub.logger.warn(
      "billing_contacts.unpermitted_params_detected",
      unpermitted_keys: extra_keys,
      all_billing_contact_keys: submitted_keys,
      content_type: request.content_type,
      xhr: request.xhr?,
      origin: request.headers["Origin"],
      turbo: request.headers["Turbo-Frame"].present?,
    )
  end
end
