# typed: strict
# frozen_string_literal: true

# THIS IS WHAT IS USED FOR THE /copilot/usage ENDPOINTS

module Copilot
  module Metrics
    class UsageMetrics
      include GitHub::Memoizer

      BreakdownMetrics = T.type_alias do
        {
          language: String,
          editor: String,
          suggestions_count: Integer,
          acceptances_count: Integer,
          lines_suggested: Integer,
          lines_accepted: Integer,
          active_users: Integer,
        }
      end

      SingleDateMetrics = T.type_alias do
        {
          day: Date,
          total_suggestions_count: Integer,
          total_acceptances_count: Integer,
          total_lines_suggested: Integer,
          total_lines_accepted: Integer,
          total_active_users: Integer,
          breakdown: T::Array[BreakdownMetrics],
        }
      end

      SingleDateMetricsWithChat = T.type_alias do
        {
          day: Date,
          total_suggestions_count: Integer,
          total_acceptances_count: Integer,
          total_lines_suggested: Integer,
          total_lines_accepted: Integer,
          total_active_users: Integer,
          total_chat_acceptances: Integer,
          total_chat_turns: Integer,
          total_active_chat_users: Integer,
          breakdown: T::Array[BreakdownMetrics],
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
      def usage_details(since_date = nil, until_date = nil)
        payload = []

        metrics = since_date || until_date ? metrics_between_dates(since_date, until_date) : all_metrics

        metrics.group_by(&:date).each do |date, records_for_date|
          totals_for_date_hash = totals_for_date(records_for_date, @entity_type, entity.id)
          totals_for_date_hash = { day: date, breakdown: [] } if totals_for_date_hash.nil?

          records_for_date.each do |metric|
            next if metric.is_totals_row?

            lang_name = if metric.language_name_id == 0 || metric.language_name_id.nil?
              metric.language.presence || "unknown"
            else
              languages[metric.language_name_id]
            end

            totals_for_date_hash[:breakdown].append({
              language: lang_name.downcase,
              editor: metric.editor,
              suggestions_count: metric.suggestions_count,
              acceptances_count: metric.acceptances_count,
              lines_suggested: metric.lines_suggested,
              lines_accepted: metric.lines_accepted,
              active_users: metric.active_users
            })
          end

          payload.append(totals_for_date_hash)
        end
        payload
      end

      private

      sig { params(since_date: T.nilable(Date), until_date: T.nilable(Date)).returns(T::Array[::Copilot::UsageMetric]) }
      def metrics_between_dates(since_date, until_date)
        if @entity_type == :organization
          Copilot::UsageMetric.for_organization(@organization).between_dates(since_date, until_date).order("date, editor, language_name_id, language ASC").to_ary
        elsif @entity_type == :business
          Copilot::UsageMetric.for_business(@business).between_dates(since_date, until_date).order("date, editor, language_name_id, language ASC").to_ary
        elsif @entity_type == :enterprise_team
          Copilot::UsageMetric.for_enterprise_team(@enterprise_team).between_dates(since_date, until_date).order("date, editor, language_name_id, language ASC").to_ary
        else
          Copilot::UsageMetric.for_team(@team).between_dates(since_date, until_date).order("date, editor, language_name_id, language ASC").to_ary
        end
      end

      sig { returns(T::Array[::Copilot::UsageMetric]) }
      memoize def all_metrics
        if @entity_type == :organization
          Copilot::UsageMetric.for_organization(@organization).last_28_days.order("date, editor, language_name_id, language ASC").to_ary
        elsif @entity_type == :business
          Copilot::UsageMetric.for_business(@business).last_28_days.order("date, editor, language_name_id, language ASC").to_ary
        elsif @entity_type == :enterprise_team
          Copilot::UsageMetric.for_enterprise_team(@enterprise_team).last_28_days.order("date, editor, language_name_id, language ASC").to_ary
        else
          Copilot::UsageMetric.for_team(@team).last_28_days.order("date, editor, language_name_id, language ASC").to_ary
        end
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

      sig do
        params(
          records_for_date: T::Array[Copilot::UsageMetric],
          entity_type: Symbol,
          entity_id: Integer
        ).returns(T.nilable(T.any(SingleDateMetrics, SingleDateMetricsWithChat)))
      end
      def totals_for_date(records_for_date, entity_type, entity_id)
        return nil unless records_for_date.any?

        totals_row = case entity_type
        when :organization
          records_for_date.find do |r|
            r.organization_id == entity_id && r.is_totals_row?
          end
        when :business
          records_for_date.find do |r|
            r.business_id == entity_id && r.organization_id.nil? && r.is_totals_row?
          end
        when :team
          records_for_date.find do |r|
            r.team_id == entity_id && r.business_id.nil? && r.organization_id.nil? && r.is_totals_row?
          end
        when :enterprise_team
          records_for_date.find do |r|
            r.enterprise_team_id == entity_id && r.business_id.nil? && r.organization_id.nil? && r.team_id.nil? && r.is_totals_row?
          end
        end

        unless totals_row
          GitHub.logger.with_named_tags({
            "gh.org.id": @organization&.id || @team&.organization&.id,
            "gh.business.id": @business&.id || @enterprise_team&.business&.id,
            "gh.team.id": @team&.id,
            "gh.enterprise_team.id": @enterprise_team&.id,
            "gh.copilot.date_for_usage_metrics": records_for_date.first&.date
          }) do
            GitHub.logger.error("Missing copilot_usage_metrics row for total unique active users for day")

            Copilot::ErrorReporter.report!(
              Copilot::Errors::UsageMetricsApiError.new("Missing copilot_usage_metrics row for total unique active users for day")
            )
            # we don't want to completely blow up because we can't find this, we just want to not include the totals
            # at the top level of the schema, and the breakdown if one exists for the day
            return nil
          end
        end

        row = T.must(totals_row)

        totals = {
          day: row.date,
          total_suggestions_count: row.suggestions_count,
          total_acceptances_count: row.acceptances_count,
          total_lines_suggested: row.lines_suggested,
          total_lines_accepted: row.lines_accepted,
          total_active_users: row.active_users,
        }

        if include_chat_metrics?
          totals.merge!(
            {
              total_chat_acceptances: row.chat_acceptances,
              total_chat_turns: row.chat_messages,
              total_active_chat_users: row.chat_active_users,
            }
          )
        end

        totals.merge!({ breakdown: [] })
      end

      sig { returns(T::Hash[Integer, String]) }
      memoize def languages
        LanguageName.all.inject({}) do |hash, language_name|
          hash[language_name.id] = language_name.name
          hash
        end
      end

      sig { returns(T.nilable(T::Boolean)) }
      def include_chat_metrics?
        case @entity_type
        when :organization
          !!(T.must(@organization).feature_flag_enabled?(:copilot_chat_metrics, default: false) || T.must(@organization).business&.feature_flag_enabled?(:copilot_chat_metrics, default: false))
        when :team
          T.must(T.must(@team).organization).feature_flag_enabled?(:copilot_chat_metrics, default: false) || T.must(T.must(@team).organization).business&.feature_flag_enabled?(:copilot_chat_metrics, default: false)
        when :business
          T.must(@business).feature_flag_enabled?(:copilot_chat_metrics, default: false)
        when :enterprise_team
          T.must(T.must(@enterprise_team).business).feature_flag_enabled?(:copilot_chat_metrics, default: false)
        else
          false
        end
      end
    end
  end
end
