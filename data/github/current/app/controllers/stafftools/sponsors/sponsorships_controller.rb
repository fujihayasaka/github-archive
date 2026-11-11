# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::SponsorshipsController < StafftoolsController
  before_action :sponsors_required
  before_action :sponsorship_required, only: [:update, :destroy]

  SPONSORSHIPS_PER_PAGE = 30

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  delegate :sponsor, :sponsorable, :tier, to: :sponsorship

  def index
    sponsorable_login = params[:sponsorable_login].presence
    sponsorables = if sponsorable_login
      User.search(sponsorable_login, with_orgs: true)
    end
    sponsor_login = params[:sponsor_login].presence
    sponsors = if sponsor_login
      User.search(sponsor_login, with_orgs: true)
    end

    sponsorships = Sponsorship.active.order(id: :desc)
    if sponsorable_login
      sponsorships = sponsorships.with_user_or_org_sponsorable(sponsorables.map(&:id))
    end
    if sponsor_login
      sponsorships = sponsorships.from_sponsor(sponsors.map(&:id))
    end
    sponsorships = sponsorships.includes(:sponsor, :sponsorable, :sponsors_listing, :tier)
      .paginate(page: current_page, per_page: SPONSORSHIPS_PER_PAGE)
    premium_sponsor_ids = Organization.active_premium_sponsor_ids(org_ids: sponsorships.map(&:sponsor_id).uniq)

    sponsors_listings = sponsorships.map(&:sponsors_listing)
    GitHub::PrefillAssociations.prefill_associations(sponsors_listings, :stafftools_metadata)

    GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :latest_billing_transaction_line_item_for_tier)

    line_items = sponsorships.map(&:latest_billing_transaction_line_item_for_tier)
    GitHub::PrefillAssociations.prefill_associations(line_items, [:billing_transaction])

    GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :via_bulk_sponsorship?)

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "stafftools/sponsors/sponsorships/sponsorships", locals: {
            sponsorships: sponsorships,
            sponsorable_login: sponsorable_login,
            sponsor_login: sponsor_login,
            premium_sponsor_ids: premium_sponsor_ids,
          }
        else
          render "stafftools/sponsors/sponsorships/index", locals: {
            sponsorships: sponsorships,
            sponsorable_login: sponsorable_login,
            sponsor_login: sponsor_login,
            premium_sponsor_ids: premium_sponsor_ids,
          }
        end
      end
    end
  end

  def update
    old_privacy_level = sponsorship.privacy_level
    success = sponsorship.update(privacy_level: sponsorship.opposite_privacy_level)

    if success
      sponsorship.instrument_privacy_level_change(actor: current_user, previous_privacy_level: old_privacy_level)

      flash[:notice] = "You've changed the privacy of #{sponsor}'s sponsorship of #{sponsorable} for #{tier.name}."
    else
      flash[:error] = "Could not change the privacy of #{sponsor}'s sponsorship of #{sponsorable} for #{tier.name}."
    end

    redirect_to billing_stafftools_user_path(sponsor)
  end

  def destroy
    # in Stafftools we allow the "cancellation" of sponsorships that have entered an invalid
    # state where the sponsorship is still active but its underlying subscription item
    # has been deactivated somehow
    result = if active_recurring_sponsorship_with_inactive_subscription_item?
      success = sponsorship.update(active: false)
      Billing::Public::ResultStruct.new(success: success, errors: sponsorship.errors.full_messages)
    else
      sponsorship.cancel(actor: current_user, reason: :STAFF_INITIATED, force: true)
    end

    if !result.success
      error_message = result.errors.to_sentence
      flash[:error] = "Could not cancel sponsorship: #{error_message}"
    else
      flash[:notice] = "You've cancelled #{sponsor}'s sponsorship of #{sponsorable} for #{tier.name}."
    end

    redirect_to billing_stafftools_user_path(sponsor)
  end

  private

  def sponsorship_required
    render_404 unless sponsorship
  end

  memoize def sponsorship
    Sponsorship.find_by(id: params[:id])
  end

  def active_recurring_sponsorship_with_inactive_subscription_item?
    subscription_item = sponsorship.subscription_item
    sponsorship.recurring_payment? && (subscription_item.nil? || subscription_item.cancelled?)
  end
end
