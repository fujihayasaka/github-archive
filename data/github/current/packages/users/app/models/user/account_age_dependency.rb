# typed: strict
# frozen_string_literal: true

module User::AccountAgeDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  requires_ancestor { User }

  # A `zero user` is any user who created an account after this date.
  # Context: https://github.com/github/octogrowth/issues/1888
  ZERO_USER_START_DATE = T.let(Time.new(2023, 02, 02).freeze, Time)

  # Public: Did this user join in the last month?
  sig { returns(T::Boolean) }
  def joined_in_last_month?
    created_at > 31.days.ago
  end

  # Public: Is this user a `zero user`?
  sig { returns(T::Boolean) }
  def zero_user?
    created_at >= ZERO_USER_START_DATE
  end

  # Public: Is this user in the new user onboarding period?
  sig { returns(T::Boolean) }
  def in_onboarding_period?
    return true if employee? && feature_enabled?(:nux_tester)

    joined_in_last_month?
  end
end
