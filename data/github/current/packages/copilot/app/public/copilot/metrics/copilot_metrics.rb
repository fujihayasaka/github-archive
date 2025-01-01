# typed: strict
# frozen_string_literal: true

# THIS IS WHAT IS USED FOR THE /copilot/metrics ENDPOINTS

module Copilot
  module Metrics
    class CopilotMetrics
      include GitHub::Memoizer

      # This is the schema version for the metrics served by the /copilot/metrics endpoints at GA
      SCHEMA_VERSION = 2

      CodeCompletionsMetrics = T.type_alias do
        {
          total_engaged_users: Integer,
          languages: T::Array[{
            name: String,
            total_engaged_users: Integer,
          }],
          editors: T::Array[{
            name: String,
            total_engaged_users: Integer,
            models: T::Array[{
              name: String,
              custom_model_training_date: T.nilable(String),
              is_custom_model: T::Boolean,
              total_engaged_users: Integer,
              languages: T::Array[{
                name: String,
                total_engaged_users: Integer,
                total_code_lines_suggested: Integer,
                total_code_lines_accepted: Integer,
                total_code_suggestions: Integer,
                total_code_acceptances: Integer,
              }]
            }]
          }]
        }
      end

      ChatMetrics = T.type_alias do
        {
          total_engaged_users: Integer,
          editors: T::Array[{
            name: String,
            total_engaged_users: Integer,
            models: T::Array[{
              name: String,
              custom_model_training_date: T.nilable(String),
              is_custom_model: T::Boolean,
              total_engaged_users: Integer,
              total_chats: Integer,
              total_chat_insertion_events: Integer,
              total_chat_copy_events: Integer,
            }]
          }]
        }
      end

      DotcomChatMetrics = T.type_alias do
        {
          total_engaged_users: Integer,
          models: T::Array[{
            name: String,
            custom_model_training_date: T.nilable(String),
            is_custom_model: T::Boolean,
            total_engaged_users: Integer,
            total_chats: Integer,
          }]
        }
      end

      DotcomPullRequestsMetrics = T.type_alias do
        {
          total_engaged_users: Integer,
          repositories: T::Array[{
            total_engaged_users: Integer,
            name: String,
            models: T::Array[{
              name: String,
              custom_model_training_date: T.nilable(String),
              is_custom_model: T::Boolean,
              total_engaged_users: Integer,
              total_pr_summaries_created: Integer,
            }]
          }],
        }
      end

      SingleDateMetrics = T.type_alias do
        {
          date: Date,
          total_active_users: Integer,
          total_engaged_users: Integer,
          copilot_ide_code_completions: CodeCompletionsMetrics,
          copilot_ide_chat: ChatMetrics,
          copilot_dotcom_chat: DotcomChatMetrics,
          copilot_dotcom_pull_requests: DotcomPullRequestsMetrics,
        }
      end

      sig { params(organization: T.nilable(::Organization), business: T.nilable(::Business), team: T.nilable(::Team), enterprise_team: T.nilable(::EnterpriseTeam)).void }
      def initialize(organization: nil, business: nil, team: nil, enterprise_team: nil)
        @organization = organization
        @business     = business
        @team         = team
        @enterprise_team = enterprise_team
        @entity_type  = T.let(if business.present?
                                :business
                              elsif team.present?
                                :team
                              elsif enterprise_team.present?
                                :enterprise_team
                              else
                                :organization
                              end, Symbol)
      end

      sig { params(since_date: T.nilable(Date), until_date: T.nilable(Date)).returns(T::Array[SingleDateMetrics]) }
      def payload(since_date = nil, until_date = nil)
        payload = []

        metrics = since_date || until_date ? metrics_between_dates(since_date, until_date) : all_metrics

        # Data served by this API is aggregated by the copilot-usage-service, which inserts copilot_usage_metrics rows into the database.
        # We're assuming the metadata column contains the entire API response and that it conforms to the sorbet types defined above.
        metrics.each do |metric|
          payload << metric.metadata
        end

        payload
      end

      private

      sig { params(since_date: T.nilable(Date), until_date: T.nilable(Date)).returns(T::Array[::Copilot::UsageMetric]) }
      def metrics_between_dates(since_date, until_date)
        if @entity_type == :organization
          Copilot::UsageMetric.for_organization(@organization, SCHEMA_VERSION).between_dates(since_date, until_date).order("date ASC").to_ary
        elsif @entity_type == :business
          Copilot::UsageMetric.for_business(@business, SCHEMA_VERSION).between_dates(since_date, until_date).order("date ASC").to_ary
        elsif @entity_type == :enterprise_team
          Copilot::UsageMetric.for_enterprise_team(@enterprise_team, SCHEMA_VERSION).between_dates(since_date, until_date).order("date ASC").to_ary
        else
          Copilot::UsageMetric.for_team(@team, SCHEMA_VERSION).between_dates(since_date, until_date).order("date ASC").to_ary
        end
      end

      sig { returns(T::Array[::Copilot::UsageMetric]) }
      memoize def all_metrics
        if @entity_type == :organization
          if flag_enabled_for_entity_or_parent?(@organization, :copilot_metrics_allow_100_days)
            Copilot::UsageMetric.for_organization(@organization, SCHEMA_VERSION).last_100_days.order("date ASC").to_ary
          else
            Copilot::UsageMetric.for_organization(@organization, SCHEMA_VERSION).last_28_days.order("date ASC").to_ary
          end
        elsif @entity_type == :business
          if flag_enabled_for_entity_or_parent?(@business, :copilot_metrics_allow_100_days)
            Copilot::UsageMetric.for_business(@business, SCHEMA_VERSION).last_100_days.order("date ASC").to_ary
          else
            Copilot::UsageMetric.for_business(@business, SCHEMA_VERSION).last_28_days.order("date ASC").to_ary
          end
        elsif @entity_type == :enterprise_team
          if flag_enabled_for_entity_or_parent?(@enterprise_team, :copilot_metrics_allow_100_days)
            Copilot::UsageMetric.for_enterprise_team(@enterprise_team, SCHEMA_VERSION).last_100_days.order("date ASC").to_ary
          else
            Copilot::UsageMetric.for_enterprise_team(@enterprise_team, SCHEMA_VERSION).last_28_days.order("date ASC").to_ary
          end
        else
          if flag_enabled_for_entity_or_parent?(@team, :copilot_metrics_allow_100_days)
            Copilot::UsageMetric.for_team(@team, SCHEMA_VERSION).last_100_days.order("date ASC").to_ary
          else
            Copilot::UsageMetric.for_team(@team, SCHEMA_VERSION).last_28_days.order("date ASC").to_ary
          end
        end
      end

      sig { params(entity: T.any(T.nilable(::Organization), T.nilable(::Business), T.nilable(::Team), T.nilable(::EnterpriseTeam)), flag_name: T.any(Symbol, String)).returns(T.nilable(T::Boolean)) }
      def flag_enabled_for_entity_or_parent?(entity, flag_name)
        enabled = FeatureFlag.vexi.enabled?(flag_name, default: false)
        return true if enabled
        return nil if entity.nil?

        enabled = entity.feature_flag_enabled?(flag_name, default: false) if entity.is_a?(::Business) || entity.is_a?(::Organization)
        enabled ||= entity.business&.feature_flag_enabled?(flag_name, default: false) if entity.is_a?(::Organization) || entity.is_a?(::Team) || entity.is_a?(::EnterpriseTeam)

        enabled
      end

      sig { returns(T.any(::Organization, ::Business, ::Team, ::EnterpriseTeam)) }
      def entity
        if @entity_type == :organization
          T.must(@organization)
        elsif @entity_type == :business
          T.must(@business)
        elsif @entity_type == :enterprise_team
          T.must(@enterprise_team)
        else
          T.must(@team)
        end
      end
    end
  end
end
