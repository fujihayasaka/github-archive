# typed: true
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for updating a sponsor's preferences about emails and privacy of their
# sponsorship.
module Sponsors
  class UpdateSponsorshipPreferences < UpdateSponsorship
    # sponsorship - the Sponsorship to update
    # is_public - Optional boolean, true if the sponsor's identity should be visible to everyone
    # email_opt_in - Optional boolean, true if the sponsor wants to receive update emails from the sponsorable
    # viewer - currently authenticated User
    # end_date - Optional Date for when the sponsorship should end; only invoiced Zuora sponsors can set this
    def self.call(sponsorship, viewer:, is_public: nil, email_opt_in: nil, end_date: nil)
      new(
        viewer: viewer,
        is_public: is_public,
        email_opt_in: email_opt_in,
        sponsorship: sponsorship,
        end_date: end_date,
      ).call
    end

    def initialize(viewer:, sponsorship:, is_public: nil, email_opt_in: nil, end_date: nil)
      raise UnprocessableError.new("No such sponsorship exists") unless sponsorship

      super(sponsorship: sponsorship, viewer: viewer)

      @sponsor = sponsorship.sponsor
      @sponsorable = sponsorship.sponsorable
      @is_public = is_public
      @email_opt_in = email_opt_in
      @end_date = end_date
    end

    def call
      super
    end

    private

    attr_reader :email_opt_in, :sponsor, :sponsorable

    def raise_unless_valid
      super
      verify_end_date_is_in_the_future
      verify_allowed_to_set_end_date
    end

    def verify_end_date_is_in_the_future
      return unless @end_date
      if @end_date <= Date.current
        raise UnprocessableError.new("Please choose an end date in the future")
      end
    end

    def verify_allowed_to_set_end_date
      return unless @end_date
      unless sponsor.sponsors_invoiced?
        raise UnprocessableError.new("You cannot set an end date for this sponsorship.")
      end
    end

    def verify_sponsorship_modifiable
      super
      # we support updating the privacy of inactive sponsorships
      verify_sponsorship_active if email_opt_in.present? || expiration_time.present?
    end

    def verify_sponsorship_active
      unless sponsorship.active?
        raise UnprocessableError.new("#{sponsor}'s sponsorship of #{sponsorable} is not active")
      end
    end

    def save_sponsorship
      sponsorship.privacy_level = privacy_level unless privacy_level.nil?
      sponsorship.is_sponsor_opted_in_to_email = email_opt_in unless email_opt_in.nil?
      sponsorship.expires_at = expiration_time unless expiration_time.nil?
      super
    end

    def privacy_level
      return if @is_public.nil?
      @is_public ? "public" : "private"
    end

    def expiration_time
      @end_date&.end_of_day
    end

    def after_sponsorship_saved
      super
      instrument_events
    end

    def instrument_events
      if privacy_level_changed? || email_opt_in_changed?
        sponsorship.instrument_preference_change(actor: viewer, previous_sponsorship: previous_sponsorship)
      end

      if privacy_level_changed?
        sponsorship.instrument_privacy_level_change(actor: viewer,
          previous_privacy_level: previous_sponsorship.privacy_level)
      end
    end

    def privacy_level_changed?
      return @privacy_level_changed if defined?(@privacy_level_changed)
      @privacy_level_changed = sponsorship.privacy_level != previous_sponsorship.privacy_level
    end

    def email_opt_in_changed?
      return @email_opt_in_changed if defined?(@email_opt_in_changed)
      @email_opt_in_changed = sponsorship.is_sponsor_opted_in_to_email !=
        previous_sponsorship.is_sponsor_opted_in_to_email
    end
  end
end
