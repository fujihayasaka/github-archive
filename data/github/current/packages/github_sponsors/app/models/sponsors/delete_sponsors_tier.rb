# typed: strict
# frozen_string_literal: true

module Sponsors

  # Public: A Plain Old Ruby Object (PORO) used for deleting an existing Sponsors tier.
  class DeleteSponsorsTier
    extend T::Sig

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    # inputs - Hash containing attributes to delete a sponsors tier
    # inputs[:tier] - The sponsorship tier to delete.
    # inputs[:viewer] - Current viewer from GraphQL context.
    sig { params(inputs: T::Hash[T.any(String, Symbol), T.untyped]).void }
    def self.call(inputs)
      new(**T.unsafe(inputs)).call
    end

    sig { params(tier: SponsorsTier, viewer: T.nilable(User)).void }
    def initialize(tier:, viewer:)
      @tier = tier
      @viewer = viewer
    end

    sig { void }
    def call
      unless tier.deletable_by?(viewer)
        raise ForbiddenError.new("#{viewer} does not have permission to delete the tier.")
      end

      unless tier.destroy
        errors = tier.errors.full_messages.join(", ")
        raise UnprocessableError.new("Could not delete tier: #{errors}")
      end
    end

    private

    sig { returns(SponsorsTier) }
    attr_accessor :tier

    sig { returns(T.nilable(User)) }
    attr_accessor :viewer
  end
end
