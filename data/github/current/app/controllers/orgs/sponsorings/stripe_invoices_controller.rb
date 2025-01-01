# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::StripeInvoicesController < Orgs::Sponsorings::BaseController
  before_action :ensure_viewer_can_create_invoice_for_org
  before_action :ensure_stripe_customer_id_is_known_for_org

  PER_PAGE = 100

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index, :new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new],
    optional: true

  sig { void }
  def index
    invoice_loader = Sponsors::StripeInvoicesLoader.new(
      customer_id: T.must(stripe_customer_id),
      status: status_param_to_enum,
      limit: PER_PAGE,
    )

    render "orgs/sponsorings/stripe_invoices/index", locals: {
      loader_result: invoice_loader.fetch,
    }
  end

  sig { void }
  def new
    render "orgs/sponsorings/stripe_invoices/new"
  end

  sig { void }
  def create
    result = Sponsors::CreateStripeInvoice.call(
      org: this_organization,
      purchase_order_number: invoice_params[:purchase_order_number],
      stripe_customer_id: stripe_customer_id,
      amount_in_dollars: invoice_params[:amount_in_dollars],
      fee_percentage: fee_percentage,
      actor: current_user,
      should_finalize: true, # We should finalize because this because this is user-initiated
    )

    if result.success?
      invoice = T.must(result.invoice)
      invoice_id = invoice["id"]
      flash[:notice] = "We've created an invoice for #{result.total_money.format} to add to " \
        "@#{this_organization.display_login}'s sponsorship balance and emailed it to #{invoice["customer_email"]}."
      redirect_to org_sponsoring_invoices_path(this_organization)
    else
      flash[:error] = result.error
      render "orgs/sponsorings/stripe_invoices/new"
    end
  end

  private

  sig { returns(ActionController::Parameters) }
  memoize def invoice_params
    params.require(:stripe_invoice).permit(:amount_in_dollars, :purchase_order_number)
  end

  sig { void }
  def ensure_viewer_can_create_invoice_for_org
    unless logged_in? && current_user.potential_organization_sponsor_ids.include?(this_organization.id)
      return render_404
    end
    render_404 unless this_organization.sponsors_invoiced?
  end

  sig { returns(Integer) }
  def fee_percentage
    Sponsorship::PERCENT_SPONSORSHIP_FEE_FOR_INVOICED_ORGS
  end

  sig { returns(Sponsors::StripeInvoicesLoader::InvoiceStatus) }
  def status_param_to_enum
    case params["status"]
    when "paid"
      Sponsors::StripeInvoicesLoader::InvoiceStatus::Paid
    else
      Sponsors::StripeInvoicesLoader::InvoiceStatus::Open
    end
  end

  sig { returns(T.nilable(String)) }
  memoize def stripe_customer_id
    this_organization.stripe_customer_id
  end

  sig { void }
  def ensure_stripe_customer_id_is_known_for_org
    if stripe_customer_id.blank?
      flash[:error] = "You must sign up for invoiced Sponsors billing to continue."
      redirect_to new_org_sponsoring_invoiced_billing_account_path(this_organization)
    end
  end
end
