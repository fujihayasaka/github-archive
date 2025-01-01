# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Invoiced::TransfersController < StafftoolsController
  extend T::Sig

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new],
    optional: true

  TRANSFERS_PER_PAGE = 20

  before_action :sponsors_required

  sig { void }
  def index
    transfers = sponsor.invoiced_sponsorship_transfers_as_sponsor.order(created_at: :desc)
      .paginate(page: current_page, per_page: TRANSFERS_PER_PAGE)

    respond_to do |format|
      format.html do
        if request.xhr?
          render Stafftools::Sponsors::Invoiced::TransfersListComponent.new(
            transfers: transfers,
            sponsor: sponsor,
          ), layout: false
        else
          render "stafftools/sponsors/invoiced/transfers/index", locals: {
            sponsor: sponsor,
            transfers: transfers,
          }
        end
      end
    end
  end

  sig { void }
  def new
    render "stafftools/sponsors/invoiced/transfers/new", locals: {
      sponsor: sponsor,
      transfer: sponsor.invoiced_sponsorship_transfers_as_sponsor.build,
    }
  end

  sig { void }
  def create
    create_transfer_and_sponsorship
    InvoicedSponsorshipTransferJob.perform_later(transfer)

    flash[:notice] = "Successfully enqueued new transfer"
    redirect_to stafftools_sponsors_invoiced_sponsor_transfers_path(sponsor)
  rescue Sponsors::CreateSponsorship::ForbiddenError,
         Sponsors::CreateSponsorship::UnprocessableError,
         Billing::CreateSubscriptionItem::UnprocessableError => err
    flash.now[:error] = "Couldn‘t create new transfer: #{err.message}"

    render "stafftools/sponsors/invoiced/transfers/new", locals: {
      sponsor: sponsor,
      transfer: transfer,
    }
  end

  sig { void }
  def destroy
    transfer = sponsor.invoiced_sponsorship_transfers_as_sponsor.find(params[:id])
    sponsorship = transfer.sponsorship
    if sponsorship.cancel(actor: current_user, reason: :STAFF_INITIATED)
      flash[:notice] = "You've cancelled the sponsorship to #{sponsorship.sponsors_listing.slug}."
    else
      flash[:error] = "#{sponsorship.sponsors_listing.slug} sponsorship cancellation failed."
    end

    redirect_to params[:redirect_to] || :back
  end

  private

  sig { returns ::Organization }
  memoize def sponsor
    Organization.find_by!(login: params[:invoiced_sponsor_id])
  end

  sig { returns InvoicedSponsorshipTransfer }
  memoize def transfer
    sponsor.invoiced_sponsorship_transfers_as_sponsor.build(transfer_params)
  end

  sig { returns T.any(Sponsorship, Billing::SubscriptionItem) }
  def create_transfer_and_sponsorship
    Sponsors::AddOneTimePayment.call(
      tier: invoiced_tier,
      sponsor: transfer.sponsor,
      sponsorable: transfer.sponsors_listing&.sponsorable,
      viewer: current_user,
      is_public: transfer.privacy_level.to_s == "public",
      email_opt_in: transfer.email_opt_in.present?,
      invoiced_transfer: transfer,
    )
  end

  sig { returns SponsorsTier }
  memoize def invoiced_tier
    SponsorsTier.new(
      sponsors_listing: transfer.sponsors_listing,
      state: :invoiced,
      creator: transfer.sponsor,
      monthly_price_in_cents: transfer.monthly_amount_in_cents,
      yearly_price_in_cents: transfer.amount_in_cents,
      description: "", # TODO: validate if this needs to be customized
      frequency: :one_time,
    ).tap { |tier| tier.name = tier.generate_name }
  end

  sig { returns ActionController::Parameters }
  def transfer_params
    params.require(:invoiced_sponsorship_transfer).permit(
      :sponsorable_login,
      :zuora_payment_id,
      :amount_in_dollars,
      :send_new_sponsor_email_on_transfer,
      :new_sponsor_email_note,
      :expires_at,
      :number_of_months,
      :privacy_level,
      :email_opt_in,
    ).merge(actor: current_user)
  end
end
