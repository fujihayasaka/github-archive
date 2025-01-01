# typed: strict
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for creating a sponsorship newsletter
module Sponsors
  class UpdateSponsorshipNewsletter
    extend T::Sig

    class UnprocessableError < StandardError; end
    class ValidationError < StandardError; end

    class Result
      extend T::Sig

      sig { returns T::Boolean }
      attr_reader :success

      sig { returns T.nilable(SponsorshipNewsletter) }
      attr_reader :newsletter

      sig { returns T.nilable(StandardError) }
      attr_reader :error

      alias_method :success?, :success

      sig do
        params(
          newsletter: T.nilable(SponsorshipNewsletter),
          success: T::Boolean,
          error: T.nilable(StandardError),
        ).void
      end
      def initialize(newsletter:, success:, error:)
        @success = success
        @newsletter = newsletter
        @error = error
      end

      sig { params(newsletter: SponsorshipNewsletter).returns(Result) }
      def self.success(newsletter)
        new(
          error: nil,
          success: true,
          newsletter: newsletter,
        )
      end

      sig { params(error: StandardError).returns(Result) }
      def self.failure(error)
        new(
          error: error,
          success: false,
          newsletter: nil,
        )
      end
    end

    sig do
      params(
        newsletter: SponsorshipNewsletter,
        body: String,
        subject: String,
        draft: T::Boolean,
        tier_ids: T.nilable(T::Array[Integer]),
      ).returns(Result)
    end
    def self.call(newsletter:, body:, subject:, draft: false, tier_ids: nil)
      new(
        newsletter: newsletter,
        body: body,
        subject: subject,
        draft: draft,
        tier_ids: tier_ids || [],
      ).call
    end

    sig do
      params(
        newsletter: SponsorshipNewsletter,
        body: String,
        subject: String,
        draft: T::Boolean,
        tier_ids: T::Array[Integer],
      ).void
    end
    def initialize(newsletter:, body:, subject:, draft: false, tier_ids: [])
      @newsletter = newsletter
      @draft = draft
      @body = body
      @subject = subject
      @tier_ids = tier_ids
    end

    sig { returns Result }
    def call
      if newsletter.published?
        error = ValidationError.new("You can't update a published sponsorship update.")
        return Result.failure(error)
      end

      newsletter.subject = subject
      newsletter.body = body
      newsletter.state = draft ? :draft : :published

      if tiers = sponsors_listing&.sponsors_tiers&.where(id: tier_ids)
        begin
          newsletter.sponsors_tiers = tiers
        rescue ActiveRecord::RecordInvalid => error
          error = UnprocessableError.new("Could not update sponsorship update: #{error.message}")
          return Result.failure(error)
        end
      end

      unless newsletter.save
        errors = newsletter.errors.full_messages.join(", ")
        error = UnprocessableError.new("Could not update sponsorship update: #{errors}")
        return Result.failure(error)
      end

      Result.success(newsletter)
    end

    private

    sig { returns SponsorshipNewsletter }
    attr_reader :newsletter

    sig { returns T::Boolean }
    attr_reader :draft

    sig { returns String }
    attr_reader :body

    sig { returns String }
    attr_reader :subject

    sig { returns T::Array[Integer] }
    attr_reader :tier_ids

    sig { returns T.nilable(SponsorsListing) }
    def sponsors_listing
      newsletter.sponsors_listing
    end
  end
end
