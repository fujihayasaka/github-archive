# typed: strict
# frozen_string_literal: true

require "faker"

module Copilot::Metrics
  module UsageReport::EnterpriseDailyFactory

    sig { params(count: Integer).returns(T::Array[UsageReport::EnterpriseDaily::TotalByIde]) }
    def self.generate_total_by_ide(count = 1)
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByIde.new(
          ide_name: Faker::App.name,
          user_initiated_interaction_count: Faker::Number.number,
          code_acceptance_activity_count: Faker::Number.number,
          code_generation_activity_count: Faker::Number.number,
          loc_suggested_to_add_sum: Faker::Number.number,
          loc_suggested_to_delete_sum: Faker::Number.number,
          loc_added_sum: Faker::Number.number,
          loc_deleted_sum: Faker::Number.number
        )
      end
    end

    sig { params(count: Integer).returns(T::Array[UsageReport::EnterpriseDaily::TotalByLanguageFeature]) }
    def self.generate_total_by_language_feature(count = 1)
      features = UsageReport::EnterpriseDaily::Feature.values.map(&:serialize).shuffle
      until features.size >= count do
        features << Faker::Internet.slug
      end
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByLanguageFeature.new(
          language: Faker::ProgrammingLanguage.name,
          feature: T.must(features.shift),
          code_acceptance_activity_count: Faker::Number.number,
          code_generation_activity_count: Faker::Number.number,
          loc_suggested_to_add_sum: Faker::Number.number,
          loc_suggested_to_delete_sum: Faker::Number.number,
          loc_added_sum: Faker::Number.number,
          loc_deleted_sum: Faker::Number.number
        )
      end
    end

    sig { params(count: Integer).returns(T::Array[UsageReport::EnterpriseDaily::TotalByFeature]) }
    def self.generate_total_by_feature(count = 1)
      features = UsageReport::EnterpriseDaily::Feature.values.map(&:serialize).shuffle
      until features.size >= count do
        features << Faker::Internet.slug
      end
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByFeature.new(
          feature: T.must(features.shift),
          user_initiated_interaction_count: Faker::Number.number,
          code_acceptance_activity_count: Faker::Number.number,
          code_generation_activity_count: Faker::Number.number,
          loc_suggested_to_add_sum: Faker::Number.number,
          loc_suggested_to_delete_sum: Faker::Number.number,
          loc_added_sum: Faker::Number.number,
          loc_deleted_sum: Faker::Number.number
        )
      end
    end

    sig { params(count: Integer).returns(T::Array[UsageReport::EnterpriseDaily::TotalByLanguageModel]) }
    def self.generate_total_by_language_model(count = 1)
      serialized_models = UsageReport::EnterpriseDaily::Model.values.map(&:serialize)
      Array.new(count) do
        UsageReport::EnterpriseDaily::TotalByLanguageModel.new(
          language: Faker::ProgrammingLanguage.name,
          model: serialized_models.sample.to_s,
          code_acceptance_activity_count: Faker::Number.number,
          code_generation_activity_count: Faker::Number.number,
          loc_suggested_to_add_sum: Faker::Number.number,
          loc_suggested_to_delete_sum: Faker::Number.number,
          loc_added_sum: Faker::Number.number,
          loc_deleted_sum: Faker::Number.number
        )
      end
    end

    sig { params(count: Integer).returns(T::Array[UsageReport::EnterpriseDaily::TotalByModelFeature]) }
    def self.generate_total_by_model_feature(count = 1)
      serialized_models = UsageReport::EnterpriseDaily::Model.values.map(&:serialize)
      model_feature_pairs = serialized_models.product(UsageReport::EnterpriseDaily::Feature.values.map(&:serialize)).shuffle
      until model_feature_pairs.size >= count do
        model_feature_pairs << [serialized_models.sample.to_s, Faker::Internet.slug.to_s]
      end
      Array.new(count) do
        pair = T.must(model_feature_pairs.shift)
        UsageReport::EnterpriseDaily::TotalByModelFeature.new(
          model: pair.first,
          feature: pair.last,
          user_initiated_interaction_count: Faker::Number.number,
          code_acceptance_activity_count: Faker::Number.number,
          code_generation_activity_count: Faker::Number.number,
          loc_suggested_to_add_sum: Faker::Number.number,
          loc_suggested_to_delete_sum: Faker::Number.number,
          loc_added_sum: Faker::Number.number,
          loc_deleted_sum: Faker::Number.number
        )
      end
    end

    sig { params(count: Integer).returns(T::Array[UsageReport::EnterpriseDaily::DayTotal]) }
    def self.generate_day_total(count = 1)
      date = Date.current.to_datetime
      Array.new(count) do
        UsageReport::EnterpriseDaily::DayTotal.new(
          day: (date = date.yesterday).to_s,
          user_initiated_interaction_count: Faker::Number.number,
          code_acceptance_activity_count: Faker::Number.number,
          code_generation_activity_count: Faker::Number.number,
          loc_suggested_to_add_sum: Faker::Number.number,
          loc_suggested_to_delete_sum: Faker::Number.number,
          loc_added_sum: Faker::Number.number,
          loc_deleted_sum: Faker::Number.number,
          daily_active_users: Faker::Number.number,
          weekly_active_users: Faker::Number.number,
          monthly_active_users: Faker::Number.number,
          monthly_active_agent_users: Faker::Number.number,
          monthly_active_chat_users: Faker::Number.number,
          totals_by_ide: generate_total_by_ide,
          totals_by_feature: generate_total_by_feature,
          totals_by_language_feature: generate_total_by_language_feature,
          totals_by_language_model: generate_total_by_language_model,
          totals_by_model_feature: generate_total_by_model_feature
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
        date: Date,
        rows: T.nilable(T::Array[T::Array[T.untyped]]), # rubocop:disable Sorbet/ForbidTUntyped
        columns: T.nilable(T::Hash[T.any(String, Symbol), String]),
      ).returns(Kusto::Data::Dataset)
    end
    def self.generate_datatable_response(enterprise_id: nil, date: Date.yesterday, rows: nil, columns: nil)
      number_of_days = 28
      columns ||= {
        day_totals: "dynamic",
        enterprise_id: "string",
        start_day: "datetime",
        end_day: "datetime",
      }

      if rows.nil?
        rows = [
          [
            generate_day_total(number_of_days).map(&:serialize),
            enterprise_id.to_s,
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
