# typed: strict
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for creating a sponsorship newsletter
module Sponsors
  class CreateSponsorshipNewsletter
    include GitHub::Memoizer

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # Public: Create a newsletter to contact sponsors.
    #
    # inputs - a Hash with the following keys:
    #   :sponsorable - the User or Organization with the GitHub Sponsors profile whose sponsors should receive the
    #                  newsletter
    #   :author - the User who is authoring the newsletter
    #   :draft - Boolean indicating whether this newsletter should be sent to sponsors immediately (false, default) or
    #            remain as a draft that only admins of the Sponsors profile can see (true)
    #   :body - String body of the newsletter; supports Markdown formatting
    #   :subject - String subject of the newsletter
    #   :tier_ids - optional Array of SponsorsTier IDs to indicate which sponsors should receive the newsletter;
    #               if given, only sponsors sponsoring at one of these tiers will be contacted; defaults to an empty
    #               list to indicate all sponsors, regardless of tier, should be contacted
    #
    # Returns a SponsorshipNewsletter on success, or raises Sponsors::CreateSponsorshipNewsletter::UnprocessableError
    # or Sponsors::CreateSponsorshipNewsletter::ForbiddenError.
    sig { params(inputs: T::Hash[T.any(String, Symbol), T.untyped]).returns(SponsorshipNewsletter) }
    def self.call(inputs)
      new(**T.unsafe(inputs)).call
    end

    sig do
      params(
        sponsorable: T.any(User, Organization),
        author: User,
        body: String,
        subject: String,
        draft: T::Boolean,
        tier_ids: T.nilable(T::Array[Integer])
      ).void
    end
    def initialize(sponsorable:, author:, body:, subject:, draft: false, tier_ids: nil)
      @sponsorable = sponsorable
      @author = author
      @draft = draft
      @body = body
      @subject = subject
      @tier_ids = T.let(tier_ids || [], T::Array[Integer])
    end

    sig { returns(SponsorshipNewsletter) }
    def call
      validate

      newsletter = build_newsletter
      unless newsletter.save
        errors = newsletter.errors.full_messages.join(", ")
        raise UnprocessableError.new("Could not save the email update: #{errors}")
      end

      newsletter
    end

    private

    sig { returns(T.any(User, Organization)) }
    attr_reader :sponsorable

    sig { returns(User) }
    attr_reader :author

    sig { returns(T::Boolean) }
    attr_reader :draft

    sig { returns(String) }
    attr_reader :body

    sig { returns(String) }
    attr_reader :subject

    sig { returns(T::Array[Integer]) }
    attr_reader :tier_ids

    delegate :sponsors_listing, to: :sponsorable

    sig { returns(SponsorshipNewsletter) }
    def build_newsletter
      SponsorshipNewsletter.new(
        sponsorable: sponsorable,
        author: author,
        state: draft ? :draft : :published,
        body: body,
        subject: subject,
      ).tap do |newsletter|
        if selected_sponsors_tiers
          newsletter.sponsors_tiers = selected_sponsors_tiers
        end
      end
    end

    sig { returns(T.nilable(T::Array[SponsorsTier])) }
    memoize def selected_sponsors_tiers
      sponsors_listing.sponsors_tiers.where(id: tier_ids).to_a if tier_ids.any?
    end

    sig { void }
    def validate
      validate_sponsors_enabled
      validate_author_permission
      validate_tiers
      validate_listing_state
    end

    sig { void }
    def validate_sponsors_enabled
      raise UnprocessableError.new("GitHub Sponsors is not available") unless GitHub.sponsors_enabled?
    end

    sig { void }
    def validate_author_permission
      unless sponsors_listing&.adminable_by?(author)
        message = if author == sponsorable
          "@#{author} does not have permission to publish a sponsors email update."
        else
          "@#{author} does not have permission to publish a sponsors email update for @#{sponsorable}."
        end
        raise ForbiddenError.new(message)
      end
    end

    sig { void }
    def validate_tiers
      return if tier_ids.empty? || tier_ids.size == T.must(selected_sponsors_tiers).size
      raise UnprocessableError.new("Not all selected tiers are valid.")
    end

    sig { void }
    def validate_listing_state
      if sponsors_listing.banned? || sponsors_listing.disabled? || !sponsors_listing.accepted_into_sponsors?
        raise ForbiddenError.new("Email updates for this Sponsors profile cannot be made at this time.")
      end
    end
  end
end
