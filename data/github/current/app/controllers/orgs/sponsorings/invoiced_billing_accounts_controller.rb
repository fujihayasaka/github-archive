# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::InvoicedBillingAccountsController < Orgs::Sponsorings::InvoicedBilling::BaseController
  before_action :ensure_account_does_not_exist
  before_action :ensure_no_active_migration_lock

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  javascript_bundle :sponsors
  stylesheet_bundle :sponsors

  sig { void }
  def new
    render "orgs/sponsorings/invoiced_billing_accounts/new", locals: {
      has_any_sponsorships: has_any_sponsorships?
    }
  end

  sig { void }
  def create
    creator = Sponsors::InvoicedSponsorAccountCreator.new(
      org: this_organization,
      name: account_params[:name] || "",
      email: account_params[:email] || "",
      address: account_params[:address]&.to_h || {},
      actor: current_user,
    )

    if creator.call
      flash[:notice] = "Thank you! We'll set up your invoiced sponsorship account and send " \
        "an email with next steps when things are ready."

      GlobalInstrumenter.instrument("sponsors.invoiced_billing_account_form_submit", {
        sponsor: this_organization,
        actor: current_user,
      })

      redirect_to settings_org_billing_path(this_organization)
    else
      base_errors = creator.errors.full_messages_for(:base)&.to_sentence
      flash[:error] = "Something went wrong: #{base_errors}" if base_errors.present?

      render "orgs/sponsorings/invoiced_billing_accounts/new", locals: {
        creator: creator,
        has_any_sponsorships: has_any_sponsorships?,
      }
    end
  end

  private

  sig { returns(ActionController::Parameters) }
  def account_params
    params.require(:account).permit(:name, :sponsorship_cancellation_confirmation, :email,
      address: [:line1, :line2, :city, :state, :country, :postal_code]
    )
  end

  sig { void }
  def ensure_account_does_not_exist
    if this_organization.sponsors_customer_account.present?
      flash[:notice] = "You've already set up an invoiced Sponsors account."
      redirect_to org_sponsoring_path(this_organization)
    end
  end

  sig { void }
  def ensure_no_active_migration_lock
    return unless this_organization.active_sponsors_invoice_migration?

    flash[:notice] = "Your organization is still being moved to invoiced billing. " \
      "We will send an email with next steps when things are ready."
    redirect_to settings_org_billing_path(this_organization)
  end

  sig { returns T::Boolean }
  def has_any_sponsorships?
    this_organization.sponsorships_as_sponsor.active.recurring.any?
  end
end
