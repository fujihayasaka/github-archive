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

    sig { params(user: ::User, editor_details: String).void }
    def self.create_for_user(user, editor_details)
      create_for_user_id(T.must(user.id), editor_details)
    end

    sig { params(user_id: Integer, editor_details: String).void }
    def self.create_for_user_id(user_id, editor_details)
      bindings = {
        user_id: user_id,
        editor_details: editor_details,
        usage_date: Time.now.utc.to_date,
        usage_hour: Time.now.utc.hour.to_i,
      }

      query = Arel.sql(<<-SQL, **bindings)
        INSERT INTO copilot_aggregate_usage_details (
          user_id,
          editor_details,
          usage_date,
          usage_hour,
          created_at,
          updated_at
        ) VALUES (
          :user_id,
          :editor_details,
          :usage_date,
          :usage_hour,
          NOW(),
          NOW()
        ) ON DUPLICATE KEY UPDATE
        usage_date = :usage_date,
        usage_hour = :usage_hour,
        editor_details = :editor_details,
        updated_at = NOW()
      SQL

      ActiveRecord::Base.connected_to(role: :writing) do
        self.connection.insert(query)
      end
    end
  end
end
