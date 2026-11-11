# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::StripeInvoicesController < StafftoolsController
  before_action :sponsors_required
  before_action :ensure_user_exists
  before_action :ensure_org_not_user

  layout "layouts/stafftools/organization/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new], optional: true

  def new
    render_new
  end

  def create
    result = Sponsors::CreateStripeInvoice.call(
      org: this_user,
      stripe_customer_id: stripe_customer_id,
      fee_percentage: fee_percentage,
      amount_in_dollars: amount_in_dollars,
      purchase_order_number: purchase_order_number,
      actor: current_user,
      # Do not finalize, since staff generated invoices need to be reviewed by Finance first.
      should_finalize: false,
    )

    if result.success?
      flash[:notice] = "Successfully created Stripe invoice for #{this_user}: #{result.invoice_url}"
      redirect_to stafftools_sponsors_invoiced_sponsors_path
    else
      flash[:error] = result.error
      render_new
    end
  end

  private

  def purchase_order_number
    params[:purchase_order_number]
  end

  def fee_percentage
    params[:fee_percentage]
  end

  def stripe_customer_id
    params[:stripe_customer_id].presence || this_user.stripe_customer_id
  end

  def amount_in_dollars
    params[:amount_in_dollars]
  end

  def render_new
    render "stafftools/sponsors/invoiced/stripe_invoices/new", locals: {
      sponsor: this_user,
      stripe_customer_id: stripe_customer_id,
      purchase_order_number: purchase_order_number,
      fee_percentage: fee_percentage,
      amount_in_dollars: amount_in_dollars,
    }
  end
end
