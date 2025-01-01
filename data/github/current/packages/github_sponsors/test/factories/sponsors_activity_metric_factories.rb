# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_activity_metric do
    sponsorable { create(:user) }

    metric { :subscription_value }
    value { 42 }
    recorded_on { Date.today }
  end
end
