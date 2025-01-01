# typed: strict
# frozen_string_literal: true

module Sponsors
  class BulkSponsorshipValidator
    extend T::Sig

    MAX_SPONSORABLES = 100

    # actor - the User who is signed in and wants to create the sponsorships on behalf of the sponsor
    # sponsor - the User or Organization who should pay for the sponsorships
    # amounts_by_sponsorable_login - Hash where the keys are String User or Organization logins for each
    #                                maintainer to be sponsored, with the value being a String USD amount such as
    #                                "2" for "$2.00"
    sig do
      params(
        actor: T.nilable(User),
        sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
        amounts_by_sponsorable_login: T::Hash[String, T.any(String, Integer, Billing::Money)],
        end_date: T.nilable(Date),
      ).void
    end
    def initialize(actor:, sponsor:, amounts_by_sponsorable_login:, end_date: nil)
      @actor = actor
      @sponsor = sponsor
      @amounts_by_sponsorable_login = amounts_by_sponsorable_login
      @end_date = end_date
      @errors = T.let([], T::Array[String])
      @is_validated = T.let(false, T::Boolean)
    end

    # Public: Are the specified parameters good enough to attempt to make the bulk sponsorships?
    sig { returns T::Boolean }
    def valid?
      errors.empty?
    end

    # Public: Human-readable error messages for any validation errors.
    sig { returns T::Array[String] }
    def errors
      validate
      @errors
    end

    private

    sig { returns T.nilable(User) }
    attr_reader :actor

    sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
    attr_reader :sponsor

    sig { returns T::Hash[String, T.any(String, Integer, Billing::Money)] }
    attr_reader :amounts_by_sponsorable_login

    sig { returns(T.nilable(Date)) }
    attr_reader :end_date

    sig { void }
    def validate
      return if @is_validated

      validate_sponsors_enabled
      validate_actor
      validate_sponsor
      validate_amounts
      validate_within_limit
      validate_end_date

      @is_validated = true
    end

    sig { void }
    def validate_sponsors_enabled
      @errors << "Could not create sponsorships: GitHub Sponsors is not available" unless GitHub.sponsors_enabled?
    end

    sig { void }
    def validate_actor
      unless actor
        @errors << "Could not create sponsorships: Actor must be specified, cannot sponsor anonymously"
        return
      end

      if actor.nil? || !T.must(actor).user?
        @errors << "Could not create sponsorships: Actor must be a user"
        return
      end

      if T.must(actor).no_verified_emails?
        @errors << "Could not create sponsorships: Actor must have a verified email"
      end

      if sponsor && !T.must(actor).potential_sponsor_ids.include?(T.must(sponsor).id)
        @errors << "Could not create sponsorships: Actor does not have permission to sponsor on behalf " \
          "of #{T.must(sponsor)}"
      end
    end

    sig { void }
    def validate_sponsor
      unless sponsor
        @errors << "Could not create sponsorships: Sponsor must be specified"
        return
      end

      if T.must(sponsor).spammy?
        whose_account = T.must(sponsor).user? ? "Your" : "#{T.must(sponsor)}'s"
        @errors << "#{whose_account} account is flagged and unable to make purchases. Please contact support " \
          "to have your account reviewed."
      end
    end

    sig { void }
    def validate_amounts
      unless amounts_by_sponsorable_login.present?
        @errors << "Could not create sponsorships: Sponsorship amounts and maintainers must be specified"
      end
    end

    sig { void }
    def validate_within_limit
      if amounts_by_sponsorable_login.size > MAX_SPONSORABLES
        @errors << "You can only sponsor up to #{MAX_SPONSORABLES} maintainers at a time."
      end
    end

    sig { void }
    def validate_end_date
      ending_date = end_date
      this_sponsor = sponsor
      return unless ending_date.present? && this_sponsor.present?

      @errors << "You cannot set an end date for these sponsorships." unless this_sponsor.sponsors_invoiced?
      @errors << "Please choose an end date in the future." unless ending_date.future?
    end
  end
end
