# typed: strict
# frozen_string_literal: true

module SponsorsHelper
  extend T::Helpers
  extend T::Sig

  include ActionView::Helpers
  include GitHub::ResilienceMixin
  include HydroHelper

  requires_ancestor { ApplicationController }

  # These sort options show up in Hydro `github.sponsors.v1.ExploreSortingChange` click events.
  MAINTAINER_SORT_OPTIONS = T.let({
    SponsorsExploreLoader::MOST_USED_SORT => "Most used",
    SponsorsExploreLoader::LEAST_USED_SORT => "Least used",
    SponsorsExploreLoader::MOST_SPONSORS_SORT => "Most sponsors",
    SponsorsExploreLoader::FEWEST_SPONSORS_SORT => "Fewest sponsors",
    SponsorsExploreLoader::NEWEST_SPONSORS_PROFILE_SORT => "Newest Sponsors profile",
    SponsorsExploreLoader::OLDEST_SPONSORS_PROFILE_SORT => "Oldest Sponsors profile",
  }.freeze, T::Hash[String, String])

  # Public: Should we show pagination controls for the "Explore GitHub Sponsors" page?
  sig { params(explore_loader: SponsorsExploreLoader).returns(T::Boolean) }
  def show_sponsorable_dependency_pagination?(explore_loader)
    paginated_list = explore_loader.paginated_sponsorables_from_dependencies
    paginated_list.total_pages > 1
  end

  sig { params(sponsors_listing: SponsorsListing, stripe_connect_eligible: T::Boolean).returns(T::Boolean) }
  def show_welcome_to_sponsors_banner?(sponsors_listing, stripe_connect_eligible:)
    !stripe_connect_eligible &&
      !sponsors_listing.approved? &&
      !current_user.dismissed_notice?("welcome_to_sponsors")
  end

  sig { params(tier_id: T.nilable(T.any(Integer, String)), state: Symbol).returns(String) }
  def no_sponsors_title(tier_id:, state:)
    tier_message = " on this tier" if tier_id.present?
    suffix = " yet" unless state == :disabled
    "You don't have any sponsors#{tier_message}#{suffix}."
  end

  sig { params(state: T.any(String, Symbol)).returns(String) }
  def no_sponsors_message(state:)
    case state
    when :disabled
      "You cannot have sponsors while your GitHub Sponsors account is disabled."
    when :approved
      "It can take some time for newly approved GitHub Sponsors profiles to get their first sponsor."
    else
      "Once you submit your GitHub Sponsors profile and it's approved, others will be able to sponsor you!"
    end
  end

  sig { params(sponsors_listing: SponsorsListing).returns(String) }
  def no_sponsors_newsletters_description(sponsors_listing)
    if sponsors_listing.disabled?
      "You cannot send updates to sponsors when your GitHub Sponsors account is disabled."
    else
      "You can let your sponsors know what you've been working on with email updates."
    end
  end

  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      listing: SponsorsListing,
      sponsoring: T::Boolean,
    ).returns(T::Boolean)
  end
  def show_sponsors_matching_fund_banner?(sponsorable, listing:, sponsoring:)
    is_matchable = -> do
      with_database_error_fallback(fallback: false) { listing.matchable? }
    end
    if !sponsoring && is_matchable.call
      if current_user&.no_verified_emails?
        false
      elsif logged_in? &&
            current_user != sponsorable &&
            !current_user.eligible_for_sponsorship_match?(sponsorable: sponsorable)
        false
      else
        true
      end
    else
      false
    end
  end

  # Public: Returns attributes to be used as data-* attributes for the toggle control for the
  # Sponsors "Need help?" tier section.
  #
  # tier_ids - an Array of integer IDs from the SponsorsTier shown in the "Need help?" section
  # open - Boolean indicating whether the "Need help?" section is open/expanded or not
  sig { params(tier_ids: T::Array[Integer], open: T::Boolean).returns(T::Hash[String, T.untyped]) }
  def sponsors_toggle_help_hydro_attrs(tier_ids, open:)
    return {} unless logged_in?

    hydro_click_tracking_attributes("sponsors.toggle_help_section", tier_ids: tier_ids, open: open)
  end

  # Public: Returns text describing the group of sponsors depending on the number of sponsorship
  sig { params(sponsorships_count: Integer).returns(String) }
  def sponsoring_users_text(sponsorships_count)
    if sponsorships_count == 1
      "organization or maintainer"
    else
      "organizations and maintainers"
    end
  end

  # Public: Get the bulk sponsorship path for the given sponsorship rows and sponsor.
  #         Depends on the presence of sponsorship_rows to either redirect to checkout or create bulk sponsorship page
  sig do
    params(
      sponsorship_rows: T::Array[Sponsors::BulkSponsorshipRow],
      sponsor: GitHubSponsors::Types::Sponsor,
      frequency: T.nilable(T.any(Symbol, String)),
    ).returns(String)
  end
  def bulk_sponsorship_path_for(sponsorship_rows:, sponsor:, frequency:)
    if sponsorship_rows.any?
      sponsors_bulk_sponsorship_checkout_path(sponsor: sponsor, frequency: frequency)
    else
      sponsors_bulk_sponsorship_imports_path(sponsor: sponsor, frequency: frequency)
    end
  end

  sig { params(sponsorship: Sponsorship).returns String }
  def opposite_email_text_for(sponsorship)
    sponsorship.is_sponsor_opted_in_to_email? ? "Unsubscribe from" : "Subscribe to"
  end

  sig { params(sponsorship: Sponsorship).returns String }
  def opposite_email_value_for(sponsorship)
    sponsorship.is_sponsor_opted_in_to_email? ? "off" : "on"
  end
end
