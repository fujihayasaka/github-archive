# typed: strict
# frozen_string_literal: true

module Copilot
  class AggregateUsageDetail < ApplicationRecord::Copilot
    include ::Instrumentation::Model

    self.table_name = "copilot_aggregate_usage_details"
    self.strict_loading_by_default = true

    belongs_to :user, class_name: "::User", strict_loading: false

    sig do
      params(users: T.any(T::Array[::User], ::User, T::Array[Integer], Integer))
      .returns(T.nilable(Copilot::AggregateUsageDetail))
    end
    def self.latest_for_users(users)
      where(user: users).order("updated_at DESC").first
    end
  end
end
