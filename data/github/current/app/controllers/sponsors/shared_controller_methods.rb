# typed: true
# frozen_string_literal: true

module Sponsors::SharedControllerMethods
  include ResilienceHelper
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController }

  included do
    extend T::Sig

    T.bind(self, T.class_of(ApplicationController))

    before_action :check_ofac_for_sponsorable

    protected

    sig { void }
    def sponsorable_required
      render_404 unless sponsorable
    end

    sig { void }
    def sponsorable_adminable_by_current_user_required
      if logged_in?
        return if sponsorable_adminable_by_viewer? || current_user.can_admin_sponsors_listings?
      end
      render_404
    end

    sig { void }
    def sponsorable_owned_by_current_user_required_for_non_get_requests
      return if request.request_method == "GET" || sponsorable_adminable_by_viewer?
      render_404
    end

    sig { void }
    def require_acceptance_into_sponsors_program
      render_404 unless GitHub.sponsors_enabled? && sponsorable_sponsors_listing&.accepted_into_sponsors?
    end

    sig { void }
    def non_waitlisted_sponsors_listing_required
      return if sponsorable_sponsors_listing && !T.must(sponsorable_sponsors_listing).waitlisted?

      if request.xhr? || pjax?
        render_404
      elsif sponsorable_adminable_by_viewer?
        redirect_to sponsorable_signup_path(sponsorable_login_param)
      else
        redirect_to user_path(sponsorable_login_param)
      end
    end

    sig { void }
    def enabled_sponsors_listing_required
      if sponsorable_sponsors_listing&.disabled?
        if request.xhr? || pjax?
          render plain: ""
        else
          redirect_to sponsorable_dashboard_path(sponsorable_login_param)
        end
      end
    end

    sig { void }
    def approved_sponsors_listing_required
      return if sponsorable_sponsors_listing&.approved?
      render_404
    end

    sig { void }
    def fiscal_host_sponsors_listing_required
      render_404 unless sponsorable_sponsors_listing&.fiscal_host?
    end

    sig { void }
    def ensure_not_fiscally_hosted
      render_404 if sponsorable_sponsors_listing&.uses_fiscal_host?
    end

    sig { void }
    def verify_visible_to_viewer
      return if sponsorable_sponsors_listing&.readable_by?(current_user)
      redirect_to user_path(sponsorable_login_param)
    end

    sig { void }
    def non_banned_sponsors_listing_required
      render_404 if sponsorable_sponsors_listing&.banned? && !current_user&.employee?
    end

    sig { void }
    def non_spammy_user_required
      return unless GitHub.spamminess_check_enabled?
      return unless sponsorable&.spammy?

      if logged_in?
        # If the viewer is associated with the spammy org or they are the spammy user, allow them to see their own
        # spammy stuff:
        return if T.must(sponsorable).adminable_by?(current_user)

        # Allow GitHub staff to see spammy stuff:
        return if current_user.employee?
      end

      render_404
    end

    sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
    def sponsorable
      return @user if defined?(@user)
      @user = if sponsorable_login_param
        User.find_by(login: sponsorable_login_param)
      end
    end

    sig { returns T.nilable(SponsorsListing) }
    def sponsorable_sponsors_listing
      return @sponsorable_sponsors_listing if defined?(@sponsorable_sponsors_listing)
      @sponsorable_sponsors_listing = sponsorable&.sponsors_listing
    end

    # Public: Memoized method to return the sponsorable metadata passed
    # from params
    sig { returns T::Hash[String, T.untyped] }
    def sponsorable_metadata_from_params
      return @sponsorable_metadata_from_params if defined?(@sponsorable_metadata_from_params)
      @sponsorable_metadata_from_params = extract_metadata_params(params)
    end

    # Public: Controller before action used to ensure if metadata is
    # properly constructed.
    #
    # Renders 404 if metadata is invalid.
    sig { void }
    def ensure_sponsorable_metadata_is_valid
      metadata = sponsorable_metadata_from_params
      return if metadata.blank?

      invalid_metadata = metadata.reject do |key, value|
        SponsorsListing::SponsorableMetadata.valid_key?(key) &&
          SponsorsListing::SponsorableMetadata.valid_value?(value)
      end

      render_404 if invalid_metadata.any?
    end

    sig { returns(T.nilable(Billing::StripeConnect::Account)) }
    def active_stripe_account
      sponsorable_sponsors_listing&.active_stripe_connect_account
    end

    sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
    def sponsor
      return @sponsor if defined? @sponsor
      @sponsor = if sponsor_login && logged_in?
        if current_user.potential_sponsor_logins.include?(sponsor_login)
          sponsor_from_params = User.find_by_login(sponsor_login)
          sponsor_from_params || current_user
        else
          current_user
        end
      elsif logged_in?
        current_user
      end
    end

    sig { params(linked_orgs: T::Boolean).returns ActiveRecord::Relation }
    def sponsorships_as_sponsorable(linked_orgs: false)
      listing = sponsorable_sponsors_listing
      return Sponsorship.none unless listing

      preload = if linked_orgs
        [{ sponsor: { sponsoring_parent_organization_profile: :organization } }, :sponsorable]
      else
        [:sponsor, :sponsorable]
      end

      sponsorships = listing.sponsorships.paid_or_patreon.preload(*preload)
      sponsorships = with_database_error_fallback(fallback: sponsorships) do
        T.unsafe(sponsorships).ranked(for_user: current_user)
      end
      sponsorships
    end

    sig { returns ActiveRecord::AssociationRelation }
    def sponsorships_for_sponsors_listing
      sponsorships = sponsorships_as_sponsorable(linked_orgs: true)

      sponsorships = sponsorships.paginate(
        page: current_page,
        per_page: Sponsors::SponsorablesController::SPONSORS_PER_PAGE
      )

      Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(
        sponsorships,
        current_user: current_user
      )
      sponsorships
    end


    # Fetches a collection of featured sponsorships for one sponsorable entity
    sig { returns ActiveRecord::Relation }
    memoize def featured_sponsorships_for_sponsors_listing
      return SponsorsListingFeaturedItem.none if featured_sponsorships.none?
      Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(
        featured_sponsorships.map(&:featureable),
        current_user: current_user
      )
      featured_sponsorships
    end

    sig { returns ActiveRecord::AssociationRelation }
    memoize def active_sponsorships_for_sponsors_listing
      all_sponsorships = sponsorships_as_sponsorable(linked_orgs: true)
      active_sponsorships = T.unsafe(all_sponsorships).active.paginate(
        page: current_page,
        per_page: Sponsors::SponsorablesController::SPONSORS_PER_PAGE
      )

      Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(
        active_sponsorships,
        current_user: current_user
      )

      active_sponsorships
    end

    sig { returns ActiveRecord::AssociationRelation }
    memoize def inactive_sponsorships_for_sponsors_listing
      all_sponsorships = sponsorships_as_sponsorable(linked_orgs: true)
      inactive_sponsorships = T.unsafe(all_sponsorships).inactive.paid_or_patreon.paginate(
        page: current_page,
        per_page: Sponsors::SponsorablesController::INACTIVE_SPONSORS_PER_PAGE
      )

      Sponsors::Profile::SponsorAvatarComponent.prefill_necessary_methods(
        inactive_sponsorships,
        current_user: current_user
      )

      inactive_sponsorships
    end

    sig { returns T.nilable(Integer) }
    def prefilled_custom_amount
      params[:amount].to_i.abs if params[:amount]
    end

    sig { returns T.nilable(String) }
    memoize def frequency_param
      params[:frequency]
    end

    sig { void }
    def valid_sponsor_required
      if logged_in?
        potential_sponsor_logins = current_user.potential_sponsor_logins
        render_404 unless potential_sponsor_logins.include?(sponsor_login)
      else
        render_404
      end
    end

    sig { returns ActiveRecord::Relation }
    def featured_users
      return SponsorsListingFeaturedItem.none unless sponsorable&.organization?

      listing = sponsorable_sponsors_listing
      return SponsorsListingFeaturedItem.none unless listing

      listing.featured_users.preload(featureable: :profile)
    end

    sig { returns ActiveRecord::Relation }
    def featured_sponsorships
      sponsorable_sponsors_listing&.featured_sponsorships&.preload(featureable: [sponsor: :profile]) ||
        SponsorsListingFeaturedItem.none
    end

    # Public: show past sponsors if both active & inactive sponsorships are present
    sig { returns T::Boolean }
    def show_sponsorship_tabs_on_sponsors_listing?
      any_featured = show_featured_sponsors_on_sponsors_profile?
      any_active = active_sponsorships_for_sponsors_listing.any?
      any_inactive = inactive_sponsorships_for_sponsors_listing.any?

      # Show sponsorship tab if at least two of above are true.
      any_active && (any_inactive || any_featured) || (any_inactive && any_featured)
    end

    # Public: show featured sponsors if there are any
    sig { returns T::Boolean }
    def show_featured_sponsors_on_sponsors_profile?
      listing = sponsorable_sponsors_listing
      return false unless listing

      listing.featured_sponsorships_settings.enabled? &&
        featured_sponsorships_for_sponsors_listing.any?
    end

    private

    sig { returns T.nilable(T::Boolean) }
    def sponsorable_adminable_by_viewer?
      return @sponsorable_adminable_by_viewer if defined?(@sponsorable_adminable_by_viewer)
      # If we can't talk to the iam-abilities cluster, conservatively assume the viewer lacks access:
      @sponsorable_adminable_by_viewer = with_database_error_fallback(fallback: false) do
        sponsorable&.adminable_by?(current_user)
      end
    end

    sig { void }
    def check_ofac_for_sponsorable
      # allow site admins and biztools users to go through
      return if current_user&.can_admin_sponsors_listings?

      check_trade_compliance(target: sponsorable)
    end

    sig { returns T.nilable(String) }
    def sponsorable_login_param
      return @sponsorable_login_param if defined?(@sponsorable_login_param)
      raw_login = params[:sponsorable_id] || params[:id]
      @sponsorable_login_param = if raw_login && GitHub::UTF8.valid_unicode3?(raw_login)
        raw_login
      end
    end

    # Private: Select sponsorable metadata params whose keys start with METADATA_KEY_PREFIX_REGEX
    sig { params(raw_params: ActionController::Parameters).returns T::Hash[String, T.untyped] }
    def extract_metadata_params(raw_params)
      # .grep + .slice combo takes half the execution time of .select
      keys = raw_params.keys.grep(SponsorsListing::SponsorableMetadata::METADATA_KEY_PREFIX_REGEX)
      metadata_params = raw_params.slice(*keys)
      metadata_params.permit!.to_h
    end

    sig { returns T.nilable(String) }
    def sponsor_login
      return @sponsor_login if defined?(@sponsor_login)
      login = params[:sponsor].presence
      @sponsor_login = login.instance_of?(String) ? login : nil # see https://github.com/github/sponsors/issues/5918
    end
  end
end
