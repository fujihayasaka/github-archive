# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::SdlcLicensingController < Stafftools::Users::BillingController
  include ::Licensing::Licensify

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  sig { void }
  def index
    render "stafftools/billing/sdlc_licensing/index", locals: { user: this_user }
  end

  sig { void }
  def update
    customer = this_user.customer

    unless customer
      flash[:error] = "No customer found for this user"
      redirect_to :back
      return
    end

    sync_customer_request = Licensify::Services::V1::SyncCustomerRequest.new(
      customerId: customer.id,
    )
    sync_customer_response = licensify_client.sync_customer(sync_customer_request)

    if sync_customer_response.error.present?
      flash[:error] = "There was an issue synchronizing licenses - #{sync_customer_response.error}"
    else
      flash[:notice] = "We're synchronizing your licenses. This may take a few minutes."
    end

    redirect_to :back
  end
end
