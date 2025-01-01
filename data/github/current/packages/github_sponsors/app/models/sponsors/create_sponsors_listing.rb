# typed: strict
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for creating a Sponsors listing
module Sponsors
  class CreateSponsorsListing
    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    FISCAL_OPTION_BANK = "bank"
    FISCAL_OPTION_HOST = "host"
    VALID_FISCAL_OPTIONS = T.let([FISCAL_OPTION_BANK, FISCAL_OPTION_HOST].freeze, T::Array[String])

    # inputs - Hash containing attributes to create a sponsors listing:
    #   :sponsorable - User or Organization who wants a Sponsors profile
    #   :parent_listing_id - Integer ID of the fiscal host's Sponsors listing, if a supported fiscal host is being
    #                        used
    #   :fiscally_hosted_project_profile_url - String URL of the hosted project's profile
    #                                          (e.g. https://numfocus.org/project/numpy); optional.
    #   :actor - currently authenticated User making this request
    #   :survey - the Survey the actor completed about signing up for Sponsors
    #   :contact_email_id - database ID for the UserEmail record we should use to contact the
    #                       sponsorable about their Sponsors membership
    #   :billing_country - String two-character country code
    #   :country_of_residence - String two-character country code
    sig { params(inputs: T::Hash[T.any(String, Symbol), T.untyped]).returns(SponsorsListing) }
    def self.with_fiscal_host(inputs)
      new(**T.unsafe(inputs.merge(fiscal_option: FISCAL_OPTION_HOST))).call
    end

    # inputs - Hash containing attributes to create a sponsors listing:
    #   :sponsorable - User or Organization who wants a Sponsors profile
    #   :actor - currently authenticated User making this request
    #   :survey - the Survey the actor completed about signing up for Sponsors
    #   :contact_email_id - database ID for the UserEmail record we should use to contact the
    #                       sponsorable about their Sponsors membership
    #   :billing_country - String two-character country code
    #   :country_of_residence - String two-character country code
    sig { params(inputs: T::Hash[T.any(String, Symbol), T.untyped]).returns(SponsorsListing) }
    def self.with_bank(inputs)
      new(**T.unsafe(inputs.merge(fiscal_option: FISCAL_OPTION_BANK))).call
    end

    sig do
      params(
        sponsorable: T.any(User, Organization),
        actor: User,
        survey: Survey,
        fiscal_option: String,
        contact_email_id: T.nilable(T.any(Integer, String)),
        billing_country: T.nilable(String),
        country_of_residence: T.nilable(String),
        parent_listing_id: T.nilable(T.any(Integer, String)),
        fiscally_hosted_project_profile_url: T.nilable(String),
        full_description: T.nilable(String)
      ).void
    end
    def initialize(sponsorable:, actor:, survey:, fiscal_option:, contact_email_id: nil, billing_country: nil, country_of_residence: nil, parent_listing_id: nil, fiscally_hosted_project_profile_url: nil, full_description: nil)
      @sponsorable = sponsorable
      @fiscal_option = fiscal_option
      @parent_listing_id = parent_listing_id
      @fiscally_hosted_project_profile_url = fiscally_hosted_project_profile_url
      @actor = actor
      @survey = survey
      @contact_email_id = contact_email_id
      @billing_country = T.let(billing_country&.upcase&.strip, T.nilable(String))
      @country_of_residence = T.let(country_of_residence&.upcase&.strip, T.nilable(String))
      @full_description = full_description
    end

    # Public: Creates a sponsors listing.
    #
    # Returns a SponsorsListing.
    # Raises UnprocessableError if the sponsorable is spammy, or if creation fails.
    # Raises ResourceMissing in development if required categories are missing.
    sig { returns(SponsorsListing) }
    def call
      validate_inputs
      listing = new_listing
      validate_sponsors_listing_before_creation(listing)
      save_sponsors_listing(listing)
      after_sponsors_listing_created(listing)
      listing
    end

    private

    sig { void }
    def validate_inputs
      validate_fiscal_host_allowed
      validate_fiscal_option
      validate_actor_permission

      # Do this after verifying the actor's permission so we don't reveal the existence of a not-yet-published
      # Sponsors profile to someone who doesn't have admin access over it:
      validate_listing_doesnt_exist_yet
    end

    sig { params(listing: SponsorsListing).void }
    def validate_sponsors_listing_before_creation(listing)
      validate_verified_email(listing)
      validate_supported_fiscal_host(listing)
    end

    sig { void }
    def validate_fiscal_host_allowed
      if fiscal_option_host? && !@sponsorable.can_use_fiscal_host_for_sponsors?
        raise UnprocessableError.new("Please specify a bank account and not a fiscal host for your " \
          "Sponsors profile.")
      end
    end

    sig { void }
    def validate_fiscal_option
      unless VALID_FISCAL_OPTIONS.include?(@fiscal_option)
        raise UnprocessableError.new("Please provide either the country/region of a bank account or " \
          "select a fiscal host.")
      end
    end

    sig { void }
    def validate_actor_permission
      permissions_message = "You can only create a GitHub Sponsors profile for yourself or an " \
        "organization you administer."
      raise ForbiddenError.new(permissions_message) if @sponsorable.user? && @actor != @sponsorable
      if @sponsorable.organization? && !@sponsorable.adminable_by?(@actor)
        raise ForbiddenError.new(permissions_message)
      end
    end

    sig { void }
    def validate_listing_doesnt_exist_yet
      if @sponsorable.sponsors_listing
        raise UnprocessableError.new("#{@sponsorable} already has a GitHub Sponsors profile")
      end
    end

    sig { params(listing: SponsorsListing).void }
    def validate_verified_email(listing)
      if listing.contact_email && !T.must(listing.contact_email).verified?
        raise UnprocessableError.new("Contact email must be verified")
      end
    end

    sig { params(listing: SponsorsListing).void }
    def validate_supported_fiscal_host(listing)
      return unless fiscal_option_host?

      allowed_parent_listing_ids = SponsorsListing.fiscal_hosts_visible_for_signup.distinct.pluck(:id).to_set
      return if allowed_parent_listing_ids.include?(listing.parent_listing_id)

      parent_sponsorable = listing.parent_listing_sponsorable
      context = ", #{parent_sponsorable}," if parent_sponsorable
      raise UnprocessableError.new("The specified fiscal host#{context} is not supported.")
    end

    sig { params(listing: SponsorsListing).returns(SponsorsListing) }
    def accept_sponsors_listing(listing)
      result = Sponsors::AcceptSponsorsMembership.call(
        sponsorable: @sponsorable.reload,
        actor: nil,
        automated: true,
        send_acceptance_email: false,
      )
      raise UnprocessableError.new(result.errors.join(", ")) unless result.success?
      listing.reload
    end

    sig { params(listing: SponsorsListing).void }
    def ban_sponsors_listing(listing)
      BanSponsorsListingJob.perform_later(
        sponsors_listing: listing,
        actor: User.staff_user,
        ban_reason: SponsorsListing.auto_ban_reason,
        automated: true,
      )
    end

    sig { void }
    def send_sponsors_listing_waitlist_confirmation_email
      SponsorsPrimerMailer.waitlist_confirmation(
        sponsorable: @sponsorable,
        waitlist_title: @survey.title,
      ).deliver_later
    end

    sig { returns(T::Boolean) }
    def fiscal_option_host?
      @fiscal_option == FISCAL_OPTION_HOST
    end

    sig { returns(SponsorsListing) }
    def new_listing
      if fiscal_option_host?
        SponsorsListing.new_with_fiscal_host(listing_params)
      else
        SponsorsListing.new_with_bank(listing_params)
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def listing_params
      short_description = "Support #{@sponsorable}'s open source work"

      if @full_description.nil?
        @full_description = short_description
      end

      result = {
        sponsorable: @sponsorable,
        survey: @survey,
        contact_email_id: @contact_email_id,
        billing_country: @billing_country,
        country_of_residence: @country_of_residence,
        short_description: short_description,
        featured_description: short_description,
        full_description: @full_description,
        created_by: @actor,
      }
      if fiscal_option_host?
        result[:fiscally_hosted_project_profile_url] = @fiscally_hosted_project_profile_url
        result[:parent_listing_id] = @parent_listing_id
      end
      result
    end

    sig { params(listing: SponsorsListing).void }
    def save_sponsors_listing(listing)
      success = T.let(true, T::Boolean)

      SponsorsListing.transaction do
        success = listing.save
        raise ActiveRecord::Rollback if success && !listing.create_stafftools_metadata
      end

      raise UnprocessableError.new(listing.errors.full_messages.join(", ")) unless success
    end

    sig { params(listing: SponsorsListing).void }
    def after_sponsors_listing_created(listing)
      update_potential_sponsorships

      if !listing.eligible_for_sponsors?
        ban_sponsors_listing(listing)
      elsif listing.auto_acceptable?
        accept_sponsors_listing(listing)
      else
        send_sponsors_listing_waitlist_confirmation_email
      end
    end

    sig { void }
    def update_potential_sponsorships
      @sponsorable.potential_sponsorships_as_sponsorable.with_states(:pending, :acknowledged)
        .each(&:mark_as_sponsors_listing_created!)
    end
  end
end
