# typed: strict
# frozen_string_literal: true

require "faker"

module Copilot::Metrics
  # NOTE: Despite the EnterpriseDailyFactory name, this factory generates
  # usage report data for both enterprise- and organization-scoped reports.
  # The name is retained for backwards compatibility.

  # ## exclude_unknown flag
  # Many generator methods accept an `exclude_unknown` parameter. When set to `true`,
  # the generated data will not include "unknown" values (e.g., Model::Unknown,
  # Feature::ChatPanelUnknownMode, or "unknown" language). This is useful for tests
  # that compare generated data against filtered results from UsageReport#fetch,
  # which filters out unknown values by default.
  module UsageReport::EnterpriseDailyFactory
    DEFAULT_NUMBER_OF_DAYS = T.let(28, Integer)

    # User count ranges for realistic data
    DAILY_ACTIVE_USERS_RANGE = T.let((50..500), T::Range[Integer])
    WEEKLY_ACTIVE_USERS_RANGE = T.let((100..1000), T::Range[Integer])
    MONTHLY_ACTIVE_USERS_RANGE = T.let((200..2000), T::Range[Integer])

    # Code interaction ranges
    USER_INTERACTION_COUNT_RANGE = T.let((100..5000), T::Range[Integer])
    CODE_ACCEPTANCE_COUNT_RANGE = T.let((50..2000), T::Range[Integer])
    CODE_GENERATION_COUNT_RANGE = T.let((200..8000), T::Range[Integer])

    # Lines of code ranges
    LOC_SUGGESTED_RANGE = T.let((500..10000), T::Range[Integer])
    LOC_ACCEPTED_RANGE = T.let((200..5000), T::Range[Integer])

    # Chat user ranges
    MONTHLY_AGENT_USERS_RANGE = T.let((200..2000), T::Range[Integer])
    MONTHLY_CHAT_USERS_RANGE = T.let((200..400), T::Range[Integer])

    sig { params(count: Integer).returns(T::Array[UsageReport::EnterpriseDaily::TotalByIde]) }
    def self.generate_total_by_ide(count = 1)
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByIde.new(
          ide_name: Faker::App.name,
          user_initiated_interaction_count: Faker::Number.between(from: USER_INTERACTION_COUNT_RANGE.min, to: USER_INTERACTION_COUNT_RANGE.max),
          code_acceptance_activity_count: Faker::Number.between(from: CODE_ACCEPTANCE_COUNT_RANGE.min, to: CODE_ACCEPTANCE_COUNT_RANGE.max),
          code_generation_activity_count: Faker::Number.between(from: CODE_GENERATION_COUNT_RANGE.min, to: CODE_GENERATION_COUNT_RANGE.max),
          loc_suggested_to_add_sum: Faker::Number.between(from: LOC_SUGGESTED_RANGE.min, to: LOC_SUGGESTED_RANGE.max),
          loc_suggested_to_delete_sum: Faker::Number.between(from: (LOC_SUGGESTED_RANGE.min / 10), to: (LOC_SUGGESTED_RANGE.max / 10)),
          loc_added_sum: Faker::Number.between(from: LOC_ACCEPTED_RANGE.min, to: LOC_ACCEPTED_RANGE.max),
          loc_deleted_sum: Faker::Number.between(from: (LOC_ACCEPTED_RANGE.min / 10), to: (LOC_ACCEPTED_RANGE.max / 10))
        )
      end
    end

    sig { params(count: Integer, exclude_unknown: T::Boolean).returns(T::Array[UsageReport::EnterpriseDaily::TotalByLanguageFeature]) }
    def self.generate_total_by_language_feature(count = 1, exclude_unknown: false)
      features = UsageReport::EnterpriseDaily::Feature.values
      features = features.reject { |f| f == UsageReport::EnterpriseDaily::Feature::ChatPanelUnknownMode } if exclude_unknown
      features = features.map(&:serialize).shuffle
      until features.size >= count do
        features << Faker::Internet.slug
      end
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByLanguageFeature.new(
          language: Faker::ProgrammingLanguage.name,
          feature: T.must(features.shift),
          code_acceptance_activity_count: Faker::Number.between(from: CODE_ACCEPTANCE_COUNT_RANGE.min, to: CODE_ACCEPTANCE_COUNT_RANGE.max),
          code_generation_activity_count: Faker::Number.between(from: CODE_GENERATION_COUNT_RANGE.min, to: CODE_GENERATION_COUNT_RANGE.max),
          loc_suggested_to_add_sum: Faker::Number.between(from: LOC_SUGGESTED_RANGE.min, to: LOC_SUGGESTED_RANGE.max),
          loc_suggested_to_delete_sum: Faker::Number.between(from: (LOC_SUGGESTED_RANGE.min / 10), to: (LOC_SUGGESTED_RANGE.max / 10)),
          loc_added_sum: Faker::Number.between(from: LOC_ACCEPTED_RANGE.min, to: LOC_ACCEPTED_RANGE.max),
          loc_deleted_sum: Faker::Number.between(from: (LOC_ACCEPTED_RANGE.min / 10), to: (LOC_ACCEPTED_RANGE.max / 10))
        )
      end
    end

    sig { params(count: Integer, exclude_unknown: T::Boolean).returns(T::Array[UsageReport::EnterpriseDaily::TotalByFeature]) }
    def self.generate_total_by_feature(count = 1, exclude_unknown: false)
      features = UsageReport::EnterpriseDaily::Feature.values
      features = features.reject { |f| f == UsageReport::EnterpriseDaily::Feature::ChatPanelUnknownMode } if exclude_unknown
      features = features.map(&:serialize).shuffle
      until features.size >= count do
        features << Faker::Internet.slug
      end
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByFeature.new(
          feature: T.must(features.shift),
          user_initiated_interaction_count: Faker::Number.between(from: USER_INTERACTION_COUNT_RANGE.min, to: USER_INTERACTION_COUNT_RANGE.max),
          code_acceptance_activity_count: Faker::Number.between(from: CODE_ACCEPTANCE_COUNT_RANGE.min, to: CODE_ACCEPTANCE_COUNT_RANGE.max),
          code_generation_activity_count: Faker::Number.between(from: CODE_GENERATION_COUNT_RANGE.min, to: CODE_GENERATION_COUNT_RANGE.max),
          loc_suggested_to_add_sum: Faker::Number.between(from: LOC_SUGGESTED_RANGE.min, to: LOC_SUGGESTED_RANGE.max),
          loc_suggested_to_delete_sum: Faker::Number.between(from: (LOC_SUGGESTED_RANGE.min / 10), to: (LOC_SUGGESTED_RANGE.max / 10)),
          loc_added_sum: Faker::Number.between(from: LOC_ACCEPTED_RANGE.min, to: LOC_ACCEPTED_RANGE.max),
          loc_deleted_sum: Faker::Number.between(from: (LOC_ACCEPTED_RANGE.min / 10), to: (LOC_ACCEPTED_RANGE.max / 10))
        )
      end
    end

    sig { params(count: Integer, exclude_unknown: T::Boolean).returns(T::Array[UsageReport::EnterpriseDaily::TotalByLanguageModel]) }
    def self.generate_total_by_language_model(count = 1, exclude_unknown: false)
      models = UsageReport::EnterpriseDaily::Model.values
      models = models.reject { |m| m == UsageReport::EnterpriseDaily::Model::Unknown } if exclude_unknown
      serialized_models = models.map(&:serialize)
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByLanguageModel.new(
          language: Faker::ProgrammingLanguage.name,
          model: serialized_models.sample.to_s,
          code_acceptance_activity_count: Faker::Number.between(from: CODE_ACCEPTANCE_COUNT_RANGE.min, to: CODE_ACCEPTANCE_COUNT_RANGE.max),
          code_generation_activity_count: Faker::Number.between(from: CODE_GENERATION_COUNT_RANGE.min, to: CODE_GENERATION_COUNT_RANGE.max),
          loc_suggested_to_add_sum: Faker::Number.between(from: LOC_SUGGESTED_RANGE.min, to: LOC_SUGGESTED_RANGE.max),
          loc_suggested_to_delete_sum: Faker::Number.between(from: (LOC_SUGGESTED_RANGE.min / 10), to: (LOC_SUGGESTED_RANGE.max / 10)),
          loc_added_sum: Faker::Number.between(from: LOC_ACCEPTED_RANGE.min, to: LOC_ACCEPTED_RANGE.max),
          loc_deleted_sum: Faker::Number.between(from: (LOC_ACCEPTED_RANGE.min / 10), to: (LOC_ACCEPTED_RANGE.max / 10))
        )
      end
    end

    sig { params(count: Integer, exclude_unknown: T::Boolean).returns(T::Array[UsageReport::EnterpriseDaily::TotalByModelFeature]) }
    def self.generate_total_by_model_feature(count = 1, exclude_unknown: false)
      models = UsageReport::EnterpriseDaily::Model.values
      models = models.reject { |m| m == UsageReport::EnterpriseDaily::Model::Unknown } if exclude_unknown
      features = UsageReport::EnterpriseDaily::Feature.values
      features = features.reject { |f| f == UsageReport::EnterpriseDaily::Feature::ChatPanelUnknownMode } if exclude_unknown
      serialized_models = models.map(&:serialize)
      model_feature_pairs = serialized_models.product(features.map(&:serialize)).shuffle
      until model_feature_pairs.size >= count do
        model_feature_pairs << [serialized_models.sample.to_s, Faker::Internet.slug.to_s]
      end
      Array.new(count) do
        pair = T.must(model_feature_pairs.shift)
        UsageReport::EnterpriseDaily::TotalByModelFeature.new(
          model: pair.first,
          feature: pair.last,
          user_initiated_interaction_count: Faker::Number.between(from: USER_INTERACTION_COUNT_RANGE.min, to: USER_INTERACTION_COUNT_RANGE.max),
          code_acceptance_activity_count: Faker::Number.between(from: CODE_ACCEPTANCE_COUNT_RANGE.min, to: CODE_ACCEPTANCE_COUNT_RANGE.max),
          code_generation_activity_count: Faker::Number.between(from: CODE_GENERATION_COUNT_RANGE.min, to: CODE_GENERATION_COUNT_RANGE.max),
          loc_suggested_to_add_sum: Faker::Number.between(from: LOC_SUGGESTED_RANGE.min, to: LOC_SUGGESTED_RANGE.max),
          loc_suggested_to_delete_sum: Faker::Number.between(from: (LOC_SUGGESTED_RANGE.min / 10), to: (LOC_SUGGESTED_RANGE.max / 10)),
          loc_added_sum: Faker::Number.between(from: LOC_ACCEPTED_RANGE.min, to: LOC_ACCEPTED_RANGE.max),
          loc_deleted_sum: Faker::Number.between(from: (LOC_ACCEPTED_RANGE.min / 10), to: (LOC_ACCEPTED_RANGE.max / 10))
        )
      end
    end

    sig { params(count: Integer, exclude_unknown: T::Boolean).returns(T::Array[UsageReport::EnterpriseDaily::DayTotal]) }
    def self.generate_day_total(count = 1, exclude_unknown: false)
      generate_day_total_with_inactive_days(count, inactive_days: 0, exclude_unknown: exclude_unknown)
    end

    # Generates day totals where the most recent `inactive_days` have zero activity,
    # simulating a scenario with data in e.g. the last 28 days but not the last 7 or 14.
    # Useful for testing the "no matching results" state locally.
    sig { params(count: Integer, inactive_days: Integer, exclude_unknown: T::Boolean).returns(T::Array[UsageReport::EnterpriseDaily::DayTotal]) }
    def self.generate_day_total_with_inactive_days(count = 1, inactive_days: 0, exclude_unknown: false)
      date = Date.current.to_datetime
      Array.new(count) do |i|
        day_date = (date = date.yesterday)
        is_inactive = i < inactive_days

        # Generate monthly active users first
        monthly_active_users_count = is_inactive ? 0 : Faker::Number.between(from: MONTHLY_ACTIVE_USERS_RANGE.min, to: MONTHLY_ACTIVE_USERS_RANGE.max)

        # Use the generated monthly active users as ceiling for agent users
        agent_users_max = [monthly_active_users_count - 1, MONTHLY_AGENT_USERS_RANGE.min].max

        UsageReport::EnterpriseDaily::DayTotal.new(
          day: day_date.to_s,
          user_initiated_interaction_count: is_inactive ? 0 : Faker::Number.between(from: USER_INTERACTION_COUNT_RANGE.min, to: USER_INTERACTION_COUNT_RANGE.max),
          code_acceptance_activity_count: is_inactive ? 0 : Faker::Number.between(from: CODE_ACCEPTANCE_COUNT_RANGE.min, to: CODE_ACCEPTANCE_COUNT_RANGE.max),
          code_generation_activity_count: is_inactive ? 0 : Faker::Number.between(from: CODE_GENERATION_COUNT_RANGE.min, to: CODE_GENERATION_COUNT_RANGE.max),
          loc_suggested_to_add_sum: is_inactive ? 0 : Faker::Number.between(from: LOC_SUGGESTED_RANGE.min, to: LOC_SUGGESTED_RANGE.max),
          loc_suggested_to_delete_sum: is_inactive ? 0 : Faker::Number.between(from: (LOC_SUGGESTED_RANGE.min / 10), to: (LOC_SUGGESTED_RANGE.max / 10)),
          loc_added_sum: is_inactive ? 0 : Faker::Number.between(from: LOC_ACCEPTED_RANGE.min, to: LOC_ACCEPTED_RANGE.max),
          loc_deleted_sum: is_inactive ? 0 : Faker::Number.between(from: (LOC_ACCEPTED_RANGE.min / 10), to: (LOC_ACCEPTED_RANGE.max / 10)),
          daily_active_users: is_inactive ? 0 : Faker::Number.between(from: DAILY_ACTIVE_USERS_RANGE.min, to: DAILY_ACTIVE_USERS_RANGE.max),
          weekly_active_users: is_inactive ? 0 : Faker::Number.between(from: WEEKLY_ACTIVE_USERS_RANGE.min, to: WEEKLY_ACTIVE_USERS_RANGE.max),
          monthly_active_users: monthly_active_users_count,
          monthly_active_agent_users: is_inactive ? 0 : Faker::Number.between(from: MONTHLY_AGENT_USERS_RANGE.min, to: agent_users_max),
          monthly_active_chat_users: is_inactive ? 0 : Faker::Number.between(from: MONTHLY_CHAT_USERS_RANGE.min, to: MONTHLY_CHAT_USERS_RANGE.max),
          totals_by_ide: is_inactive ? [] : generate_total_by_ide,
          totals_by_feature: is_inactive ? [] : generate_total_by_feature(exclude_unknown: exclude_unknown),
          totals_by_language_feature: is_inactive ? [] : generate_total_by_language_feature(exclude_unknown: exclude_unknown),
          totals_by_language_model: is_inactive ? [] : generate_total_by_language_model(exclude_unknown: exclude_unknown),
          totals_by_model_feature: is_inactive ? [] : generate_total_by_model_feature(exclude_unknown: exclude_unknown)
        )
      end
    end

    # Alternative method with explicit control over user counts
    sig do
      params(
        count: Integer,
        daily_active_users: T.nilable(Integer),
        weekly_active_users: T.nilable(Integer),
        monthly_active_users: T.nilable(Integer),
        exclude_unknown: T::Boolean
      ).returns(T::Array[UsageReport::EnterpriseDaily::DayTotal])
    end
    def self.generate_day_total_with_custom_users(count = 1, daily_active_users: nil, weekly_active_users: nil, monthly_active_users: nil, exclude_unknown: false)
      date = Date.current.to_datetime
      Array.new(count) do
        # Generate or use provided monthly active users
        monthly_active_users_count = monthly_active_users || Faker::Number.between(from: MONTHLY_ACTIVE_USERS_RANGE.min, to: MONTHLY_ACTIVE_USERS_RANGE.max)

        # Use the generated/provided monthly active users as ceiling for agent users
        agent_users_max = [monthly_active_users_count - 1, MONTHLY_AGENT_USERS_RANGE.min].max

        UsageReport::EnterpriseDaily::DayTotal.new(
          day: (date = date.yesterday).to_s,
          user_initiated_interaction_count: Faker::Number.between(from: USER_INTERACTION_COUNT_RANGE.min, to: USER_INTERACTION_COUNT_RANGE.max),
          code_acceptance_activity_count: Faker::Number.between(from: CODE_ACCEPTANCE_COUNT_RANGE.min, to: CODE_ACCEPTANCE_COUNT_RANGE.max),
          code_generation_activity_count: Faker::Number.between(from: CODE_GENERATION_COUNT_RANGE.min, to: CODE_GENERATION_COUNT_RANGE.max),
          loc_suggested_to_add_sum: Faker::Number.between(from: LOC_SUGGESTED_RANGE.min, to: LOC_SUGGESTED_RANGE.max),
          loc_suggested_to_delete_sum: Faker::Number.between(from: (LOC_SUGGESTED_RANGE.min / 10), to: (LOC_SUGGESTED_RANGE.max / 10)),
          loc_added_sum: Faker::Number.between(from: LOC_ACCEPTED_RANGE.min, to: LOC_ACCEPTED_RANGE.max),
          loc_deleted_sum: Faker::Number.between(from: (LOC_ACCEPTED_RANGE.min / 10), to: (LOC_ACCEPTED_RANGE.max / 10)),
          daily_active_users: daily_active_users || Faker::Number.between(from: DAILY_ACTIVE_USERS_RANGE.min, to: DAILY_ACTIVE_USERS_RANGE.max),
          weekly_active_users: weekly_active_users || Faker::Number.between(from: WEEKLY_ACTIVE_USERS_RANGE.min, to: WEEKLY_ACTIVE_USERS_RANGE.max),
          monthly_active_users: monthly_active_users_count,
          monthly_active_agent_users: Faker::Number.between(from: MONTHLY_AGENT_USERS_RANGE.min, to: agent_users_max),
          monthly_active_chat_users: Faker::Number.between(from: MONTHLY_CHAT_USERS_RANGE.min, to: MONTHLY_CHAT_USERS_RANGE.max),
          totals_by_ide: generate_total_by_ide,
          totals_by_feature: generate_total_by_feature(exclude_unknown: exclude_unknown),
          totals_by_language_feature: generate_total_by_language_feature(exclude_unknown: exclude_unknown),
          totals_by_language_model: generate_total_by_language_model(exclude_unknown: exclude_unknown),
          totals_by_model_feature: generate_total_by_model_feature(exclude_unknown: exclude_unknown)
        )
      end
    end

    sig { params(columns: T::Hash[T.any(String, Symbol), String]).returns(T::Array[T::Hash[String, String]]) }
    def self.generate_columns(columns)
      columns.map do |name, type|
        {
          "ColumnName": name.to_s,
          "ColumnType": type.to_s
        }.stringify_keys
      end
    end

    sig do
      params(
        enterprise_id: T.nilable(Integer),
        organization_id: T.nilable(Integer),
        date: Date,
        rows: T.nilable(T::Array[T::Array[T.untyped]]), # rubocop:disable Sorbet/ForbidTUntyped
        columns: T.nilable(T::Hash[T.any(String, Symbol), String]),
        number_of_days: Integer,
        inactive_days: Integer,
        exclude_unknown: T::Boolean,
      ).returns(Kusto::Data::Dataset)
    end
    def self.generate_datatable_response(enterprise_id: nil, organization_id: nil, date: Date.yesterday, rows: nil, columns: nil, number_of_days: DEFAULT_NUMBER_OF_DAYS, inactive_days: 0, exclude_unknown: false)
      # number_of_days is now configurable via parameter or environment variable
      columns ||= {
        :day_totals => "dynamic",
        (organization_id ? :organization_id : :enterprise_id) => "string",
        :start_day => "datetime",
        :end_day => "datetime",
      }

      if rows.nil?
        # Determine which ID to use (organization_id takes precedence)
        entity_id = organization_id || enterprise_id
        rows = [
          [
            generate_day_total_with_inactive_days(number_of_days, inactive_days: inactive_days, exclude_unknown: exclude_unknown).map(&:serialize),
            entity_id.to_s,
            (date - number_of_days.days).iso8601,
            date.iso8601,
          ]
        ]
      end

      datatable = [
        {
          "FrameType": "DataTable",
          "TableId": 1,
          "TableKind": "PrimaryResult",
          "TableName": "PrimaryResult",
          "Columns": generate_columns(columns),
          "Rows": rows
        }.stringify_keys
      ]
      Kusto::Data::Dataset.new(datatable)
    end
  end
end
