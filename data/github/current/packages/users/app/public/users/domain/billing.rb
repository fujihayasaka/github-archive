# typed: strict
# frozen_string_literal: true

module Users
  class Domain
    class Billing < GH::Domain::Base

      # update a user's billing data
      sig do
        params(
          user: User,
          plan: T.any(String, GH::Omit),
          plan_duration: T.any(String, GH::Omit),
          billed_on: T.nilable(T.any(Date, GH::Omit)),
          billing_attempts: T.any(Integer, GH::Omit),
          seats: T.any(Integer, GH::Omit),
          disabled: T.any(T::Boolean, GH::Omit),
          raise: T::Boolean,
        ).returns(T::Boolean)
      end
      def update(user:,
        plan: GH::OMIT,
        plan_duration: GH::OMIT,
        billed_on: GH::OMIT,
        billing_attempts: GH::OMIT,
        seats: GH::OMIT,
        disabled: GH::OMIT,
        raise: false
      )
        # add disabled?
        attrs = { plan:, plan_duration:, billed_on:, billing_attempts:, seats:, disabled: }
        attrs.reject! { |_, v| v == GH::OMIT }
        raise ? user.update!(attrs) : user.update(attrs)
      end

      # update a user's billing data without callbacks/validations
      sig do
        params(
          user: User,
          plan: T.any(String, GH::Omit),
          billed_on: T.nilable(T.any(Date, GH::Omit)),
          billing_attempts: T.any(Integer, GH::Omit),
        ).returns(T::Boolean)
      end
      def update_columns(user:, plan: GH::OMIT, billed_on: GH::OMIT, billing_attempts: GH::OMIT)
        # add billing_attempts, seats, disabled
        attrs = { plan:, billed_on:, billing_attempts: }
        attrs.reject! { |_, v| v == GH::OMIT }
        result = if attrs.keys.length > 1
          user.update_columns(attrs)
        elsif attrs.keys.length == 1
          user.update_column(attrs.keys.first, attrs.values.first)
        end
        user.invalidate_cache("users_billing_update_columns")
        result
      end
    end
  end
end
