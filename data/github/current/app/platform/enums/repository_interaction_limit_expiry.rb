# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryInteractionLimitExpiry < Platform::Enums::Base
      description "The length for a repository interaction limit to be enabled for."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "ONE_DAY", "The interaction limit will expire after 1 day.", value: :one_day
      value "THREE_DAYS", "The interaction limit will expire after 3 days.", value: :three_days
      value "ONE_WEEK", "The interaction limit will expire after 1 week.", value: :one_week
      value "ONE_MONTH", "The interaction limit will expire after 1 month.", value: :one_month
      value "SIX_MONTHS", "The interaction limit will expire after 6 months.", value: :six_months
    end
  end
end
