# typed: strict
# frozen_string_literal: true

module Copilot
  class BillingEntityResolver
    class Result < T::Struct
      const :business, T.nilable(::Business)
      const :organization, T.nilable(::Organization)

      sig { returns(T.nilable(String)) }
      def display_name
        organization_display_name.presence || business_display_name
      end

      sig { returns(T.nilable(String)) }
      def organization_display_name
        organization&.display_name&.presence || organization&.display_login
      end

      sig { returns(T.nilable(String)) }
      def business_display_name
        business&.name&.presence || business&.slug
      end
    end

    EMPTY_BILLING_ENTITY = T.let(
      Result.new(business: nil, organization: nil),
      Result,
    )

    sig { returns(User) }
    attr_reader :copilot_user

    sig { params(copilot_user: User).void }
    def initialize(copilot_user)
      @copilot_user = copilot_user
    end

    # The limiter codepath requires us to load the provider and, if we can load via seats then
    # override the provider with the seat billing entity. Other codepaths switch based on multi-access.
    sig { params(default_to_provider: T::Boolean).returns(Result) }
    def resolve(default_to_provider: false)
      if default_to_provider
        provider_result = billing_entity_from_provider
        return provider_result unless copilot_user.has_multi_access?

        seats_result = billing_entity_from_seats
        return seats_result if seats_result.organization || seats_result.business

        provider_result
      else
        if copilot_user.has_multi_access?
          billing_entity_from_seats
        else
          billing_entity_from_provider
        end
      end
    end

    private

    sig { returns(Result) }
    def billing_entity_from_provider
      copilot_provider = copilot_user.copilot_provider
      case copilot_provider
      when Organization
        business = copilot_provider.business
        Result.new(
          business: business,
          organization: copilot_provider.organization_object,
        )
      when Business
        business = copilot_provider.business_object
        Result.new(
          business: business,
          organization: nil,
        )
      else
        EMPTY_BILLING_ENTITY
      end
    end

    sig { returns(Result) }
    def billing_entity_from_seats
      return EMPTY_BILLING_ENTITY unless copilot_user.billable_customer_id

      seat = Seat.for_user(copilot_user.user_object).find do |s|
        assignment = s.seat_assignment
        next unless assignment

        assignment.owner.present? &&
          s.customer_id == copilot_user.billable_customer_id
      end

      return EMPTY_BILLING_ENTITY unless seat

      assignment = seat.seat_assignment
      return EMPTY_BILLING_ENTITY unless assignment

      owner = assignment.owner
      case owner
      when ::Organization
        business = owner.business
        Result.new(
          business: business,
          organization: owner,
        )
      when ::Business
        Result.new(
          business: owner,
          organization: nil,
        )
      else
        EMPTY_BILLING_ENTITY
      end
    end
  end
end
