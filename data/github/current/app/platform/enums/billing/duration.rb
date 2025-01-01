# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module Billing
      class Duration < Platform::Enums::Base
        graphql_name "BillingDuration"
        description "The plan duration of a billing subscription. e.g month, year"

        visibility :internal

        value "MONTH", "The Subscription is billed monthly.", value: "month"
        value "YEAR", "The Subscription is billed yearly.", value: "year"
      end
    end
  end
end
