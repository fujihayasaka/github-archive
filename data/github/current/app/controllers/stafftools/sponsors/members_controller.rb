# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::MembersController < Stafftools::SponsorsController
  include PlatformHelper

  before_action :sponsors_listing_required, only: [:show, :update, :destroy]

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

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  PER_PAGE = 100
  DEFAULT_ORDER = "most_recent_status_change"
  CHILD_LISTINGS_PER_PAGE = 5
  PERMITTED_FILTER_PARAMS = [:state, :spammy, :featured, :suspended, :matchable, :type, :ignored, fiscal_host: [],
    billing_country: [], country_of_residence: [], flags: []].freeze

  def index
    filter = index_params[:filter].to_h.presence || default_index_filter
    query = index_params[:query] || ""
    spammy = if filter.key?(:spammy) && filter[:spammy] != "all"
      filter[:spammy] == "1"
    end
    featured = if filter.key?(:featured) && filter[:featured] != "all"
      filter[:featured] == "1"
    end
    suspended = if filter.key?(:suspended) && filter[:suspended] != "all"
      filter[:suspended] == "1"
    end
    matchable = filter[:matchable] == "1" if filter.key?(:matchable)
    state = filter[:state].presence
    order = index_params[:order].presence || DEFAULT_ORDER
    user_type = filter[:type].presence
    fiscal_host = filter[:fiscal_host].presence
    ignored = if filter.key?(:ignored) && filter[:ignored] != "all"
      filter[:ignored] == "1"
    end
    billing_countries = filter[:billing_country] if filter.key?(:billing_country)
    countries_of_residence = filter[:country_of_residence] if filter.key?(:country_of_residence)
    flags = filter[:flags] if filter.key?(:flags)

    listings = SponsorsListing.
      filter_by_state(state).
      filter_by_featured(featured).
      filter_by_fiscal_host(fiscal_host).
      filter_by_sponsorable_spamminess(spammy).
      filter_by_sponsorable_suspendedness(suspended).
      filter_by_user_type(user_type).
      filter_by_ignored_status(ignored).
      filter_by_billing_country(billing_countries).
      filter_by_country_of_residence(countries_of_residence).
      filter_by_matchableness(matchable).
      filter_by_flags(flags)

    listings = listings.
      matches_slug_or_description(query).
      ordered_by_named_sort(order).
      paginate(page: current_page, per_page: PER_PAGE).
      includes(:stafftools_metadata)

    fiscal_host_listings = SponsorsListing.fiscal_hosts
      .ordered_by_sponsorable_login
      .includes(:stafftools_metadata)

    all_listings = fiscal_host_listings + listings
    GitHub::PrefillAssociations.prefill_associations(all_listings, { sponsorable: :profile })
    GitHub::PrefillAssociations.prefill_associations(all_listings, :active_stripe_connect_account)

    active_stripe_accounts = listings.map(&:active_stripe_connect_account).compact
    transfer_counts_by_stripe_connect_account_id = load_stripe_transfer_counts(active_stripe_accounts)

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "stafftools/sponsors/members/listings", locals: {
            listings: listings,
            filter: filter,
            order: order,
            query: query,
            fiscal_host_listings: fiscal_host_listings,
            transfer_counts_by_stripe_connect_account_id: transfer_counts_by_stripe_connect_account_id,
          }
        else
          render "stafftools/sponsors/members/index", locals: {
            listings: listings,
            filter: filter,
            order: order,
            query: query,
            fiscal_host_listings: fiscal_host_listings,
            transfer_counts_by_stripe_connect_account_id: transfer_counts_by_stripe_connect_account_id,
          }
        end
      end
    end
  end

  def show
    child_listings = if this_listing.fiscal_host?
      this_listing
        .child_listings
        .oldest_join_date_first
        .includes(sponsorable: :profile)
        .paginate(page: current_page, per_page: CHILD_LISTINGS_PER_PAGE)
    else
      []
    end

    if pjax? && this_listing.fiscal_host?
      render partial: "stafftools/sponsors/members/child_listings", locals: {
        child_listings: child_listings,
      }, layout: false
    else
      manual_criteria = SponsorsMembershipsCriterion.manual.includes(:sponsors_criterion)
        .where(sponsors_listing_id: this_listing)

      hooks = if this_listing
        Hook::StatusLoader.load_statuses(
          hook_records: this_listing.hooks,
          parent: this_listing,
        )
      end

      staff_notes = this_listing.staff_notes.includes(:user).order(created_at: :desc)
      stripe_connect_accounts = this_listing.stripe_connect_accounts.active_first
      transfer_counts_by_stripe_connect_account_id =
        load_stripe_transfer_counts(stripe_connect_accounts)

      view = create_view_model(Stafftools::Sponsors::Members::ShowView, listing: this_listing)
      render "stafftools/sponsors/members/show",
        layout: "application",
        locals: {
          sponsorable: this_sponsorable,
          listing: this_listing,
          manual_criteria: manual_criteria,
          hooks: hooks,
          staff_notes: staff_notes,
          view: view,
          child_listings: child_listings,
          pinned_repos: pinned_repos,
          stripe_connect_accounts: stripe_connect_accounts,
          transfer_counts_by_stripe_connect_account_id: transfer_counts_by_stripe_connect_account_id,
          sponsorable_has_sponsored: this_sponsorable.has_ever_sponsored?,
          sponsors_fraud_reviews: sponsors_fraud_reviews,
          flagged_sponsor_records: flagged_sponsor_records,
          sponsors_activities: sponsors_activities,
        }
    end
  end

  def update
    old_fiscal_host = this_listing.human_fiscal_host
    this_listing.assign_attributes(listing_update_params)

    using_new_supported_fiscal_host = fiscal_host_type == "supported" && this_listing.parent_listing_id_changed?
    stripe_account = this_listing.active_stripe_connect_account
    should_deactivate_stripe_account = using_new_supported_fiscal_host && stripe_account.present?

    if should_deactivate_stripe_account
      unless stripe_account.update(active: false)
        flash[:error] = "Could not deactivate @#{this_sponsorable}'s active Stripe Connect account: " +
          stripe_account.errors.full_messages.to_sentence
        return
      end

      this_listing.reload_active_stripe_connect_account
    end

    if this_listing.save
      flash[:notice] = "Successfully updated @#{this_sponsorable}'s GitHub Sponsors profile."
    else
      listing_errors = this_listing.errors.full_messages

      flash[:error] = if !should_deactivate_stripe_account || stripe_account.update(active: true)
        listing_errors.uniq.to_sentence
      else
        "Failed to update the GitHub Sponsors profile after deactivating @#{this_sponsorable}'s " \
          "Stripe Connect account, then failed to reactivate the Stripe account: " +
          (listing_errors + stripe_account.errors.full_messages).uniq.to_sentence
      end
    end

    if using_new_supported_fiscal_host
      this_listing.instrument_fiscal_host_change(old_fiscal_host: old_fiscal_host, actor: current_user)
    end
  ensure
    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  def destroy
    this_listing.deletion_confirmation = params[:confirm]
    this_listing.destroy!
    flash[:notice] = "Successfully deleted @#{this_sponsorable}'s GitHub Sponsors profile."
    redirect_to stafftools_sponsors_members_path
  rescue ActiveRecord::RecordNotDestroyed => error
    flash[:error] = error.record.errors.full_messages.to_sentence
    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  private

  def default_index_filter
    HashWithIndifferentAccess.new("ignored" => "0", "state" => "pending_approval", "spammy" => "0",
      "suspended" => "0", "billing_country" => ["supported"])
  end

  memoize def index_params
    params.permit(:mysql_query_trace, :query, :utf8, :page, :order, filter: PERMITTED_FILTER_PARAMS)
  end

  def fiscal_host_type
    params[:fiscal_host_type]
  end

  memoize def listing_update_params
    return {} unless params.key?(:sponsors_listing)

    params.require(:sponsors_listing)
      .permit(:contact_email_id, :is_fiscal_host, :billing_country, :parent_listing_id)
      .to_h
  end

  def load_stripe_transfer_counts(stripe_connect_accounts)
    counts = Billing::PayoutsLedgerEntry.net_transfers
      .for_stripe_account(stripe_connect_accounts)
      .group(:stripe_connect_account_id)
      .count
    Hash.new(0).merge(counts)
  end

  memoize def pinned_repos
    this_sponsorable.pinned_repositories.includes(:owner)
  end

  memoize def sponsors_fraud_reviews
    this_listing
      .fraud_reviews
      .includes(:reviewer)
      .order(created_at: :desc)
  end

  memoize def flagged_sponsor_records
    FraudFlaggedSponsor
      .where(sponsors_fraud_review_id: sponsors_fraud_reviews)
      .includes(:sponsor)
      .order(created_at: :desc)
  end

  memoize def sponsors_activities
    this_sponsorable
      .sponsors_activities
      .with_sponsorable_action
      .order(timestamp: :desc)
      .paginate(page: 1, per_page: Stafftools::Sponsors::Members::ActivitiesController::PER_PAGE)
  end
end
