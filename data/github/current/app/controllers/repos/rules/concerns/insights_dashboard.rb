# typed: strict
# frozen_string_literal: true

require "react_payload"

module Repos
  module Rules
    module Concerns
      module InsightsDashboard
        extend ActiveSupport::Concern
        extend T::Helpers

        requires_ancestor { ApplicationController }

        # Hooks

        sig do
          params(source: T.nilable(T.any(Repository, Organization, Business)), user: T.nilable(User)).void
        end
        def rule_insights_dashboard_enabled(source: nil, user: nil)
          render_404 unless (
            source&.feature_enabled_for_source?(:rule_insights_dashboard) ||
            user&.feature_flag_enabled?(:rule_insights_dashboard, default: false)
          )
        end

        sig do
          params(source: T.nilable(T.any(Repository, Organization, Business)), user: T.nilable(User)).void
        end
        def rule_insights_dashboard_org_enabled(source: nil, user: nil)
          render_404 unless (
            source&.feature_enabled_for_source?(:rule_insights_dashboard_org) ||
            user&.feature_flag_enabled?(:rule_insights_dashboard_org, default: false)
          )
        end

        # React DataRouter

        class DashboardRoutePayload < ::ReactPayload::Base
          include Repos::Rules::CreatedDateFilter

          sig { override.returns(String) }
          def route_id
            "dashboardRoute"
          end

          EVALUATE_STATUSES = T.let(%w[active all evaluate].freeze, T::Array[String])

          sig do
            params(
              source: RuleEngine::Types::RuleSource,
              user: User,
              filter: T::Hash[Symbol, T.nilable(String)],
              insights_path: String,
            ).void
          end
          def initialize(source:, user:, filter: {}, insights_path: "")
            @source = source
            @user = user

            insights_url = Addressable::URI.parse(insights_path)
            insights_url.query_values = {
              rule_status: "pass"
            }
            @allowed_insights_url = T.let(insights_url.to_s, String)
            insights_url.query_values = {
              rule_status: "fail"
            }
            @failed_insights_url = T.let(insights_url.to_s, String)
            insights_url.query_values = {
              rule_status: "bypass"
            }
            @bypassed_insights_url = T.let(insights_url.to_s, String)

            rulesets = RepositoryRuleset.load_for(source: @source, include_parents: false)

            @ruleset = T.let(
              filter[:ruleset_name].present? ? rulesets.find { |rs| rs.name == filter[:ruleset_name] } : nil,
              T.nilable(RepositoryRuleset),
            )
            @evaluate_status = T.let(
              EVALUATE_STATUSES.include?(filter[:evaluate_status]) ? T.must(filter[:evaluate_status]) : "active",
              String,
            )
            @branch = T.let(
              filter[:branch].is_a?(String) ? filter[:branch] : nil,
              T.nilable(String),
            )
            @branch_is_valid = T.let(
              if @source.is_a?(Repository)
                @branch.blank? || !!@source.branch_exists?(@branch)
              else
                nil
              end,
              T.nilable(T::Boolean),
            )
            @rulesets = T.let(rulesets, T::Enumerable[RepositoryRuleset])
            @created = T.let(
              filter[:created].is_a?(String) ? filter[:created] : ">@today-1w",
              T.nilable(String),
            )

            parsed = parse_created_filter(@created, @user)
            @from = T.let(parsed[:from], T.nilable(Time))
            @to = T.let(parsed[:to], T.nilable(Time))
          end

          MAX_LOOKBACK_DAYS = 30
          sig do
            params(
              created: T.nilable(String),
              user: User,
            )
            .returns({ from: T.nilable(Time), to: T.nilable(Time) })
          end
          def parse_created_filter(created, user)
            default_from = T.let(1.week.ago, Time)
            default_to = T.let(Time.current, Time)

            return { from: default_from, to: default_to } if created.blank?

            user_time_zone = user.time_zone
            current_date = Time.now.in_time_zone(user_time_zone).to_date
            max_lookback = current_date - MAX_LOOKBACK_DAYS

            # GT/LT ranges are capped at 30 days for the dashboard
            parsed = parse_created_date_value(created, timezone: user_time_zone, gt_lt_cap_days: MAX_LOOKBACK_DAYS)

            # Unrecognized or invalid format → fall back to defaults
            return { from: default_from, to: default_to } if parsed.nil?

            # Clamp so we never look back further than 30 days and never past today
            clamped = clamp_created_filter(parsed, max_lookback, current_date: current_date)
            return { from: default_from, to: default_to } if clamped.nil?

            # Convert Date / Range<Date> → { from: Time, to: Time }
            created_date_to_time_range(clamped)
          end

          sig do
            override.returns(T::Hash[String, T.untyped])
          end
          def payload
            filter_hash = {
              ruleset: @ruleset.present? ? { name: @ruleset.name } : nil,
              evaluateStatus: @evaluate_status,
              created: @created,
            }
            filter_hash[:branch] = @branch if @branch.present?


            result = {
              sourceType: source_type,
              filter: filter_hash,
              rulesets: @rulesets.map { |rs| { name: rs.name } },
              ruleSuites: [{
                name: "Passes",
                data: with_query_telemetry("count_by_day_pass") do
                  rule_suite_count_in_timespan_by_day(rule_status: "pass", from: @from, to: @to)
                end,
              }, {
                name: "Failures",
                data: with_query_telemetry("count_by_day_fail") do
                  rule_suite_count_in_timespan_by_day(rule_status: "fail", from: @from, to: @to)
                end,
              }, {
                name: "Bypasses",
                data: with_query_telemetry("count_by_day_bypass") do
                  rule_suite_count_in_timespan_by_day(rule_status: "bypass", from: @from, to: @to)
                end,
              }],
              metrics: [
                Metric.new(
                  name: "Allowed",
                  value: with_query_telemetry("count_by_status_pass") do
                    rule_suite_count_in_timespan(rule_status: "pass", from: @from, to: @to)
                  end,
                  link: {
                    displayText: "View allowed runs",
                    href: @allowed_insights_url,
                  },
                ),
                Metric.new(
                  name: "Failed",
                  value: with_query_telemetry("count_by_status_fail") do
                    rule_suite_count_in_timespan(rule_status: "fail", from: @from, to: @to)
                  end,
                  link: {
                    displayText: "View failed runs",
                    href: @failed_insights_url,
                  },
                ),
                Metric.new(
                  name: "Bypassed",
                  value: with_query_telemetry("count_by_status_bypass") do
                    rule_suite_count_in_timespan(rule_status: "bypass", from: @from, to: @to)
                  end,
                  link: {
                    displayText: "View bypassed runs",
                    href: @bypassed_insights_url,
                  },
                ),
              ],
              bypassesByActor: with_query_telemetry("count_bypasses_by_actor") do
                rule_suite_count_in_timespan_by_actor(from: @from, to: @to)
              end,
            }
            result[:branchIsValid] = @branch_is_valid unless @branch_is_valid.nil?
            if @source.is_a?(Repository)
              result[:source] = {
                ownerLogin: @source.owner_display_login,
                name: @source.name,
              }
            end
            result
          end

          sig { returns(String) }
          def source_type
            if @source.is_a?(Repository)
              "repository"
            elsif @source.is_a?(Organization)
              "organization"
            else
              "enterprise"
            end
          end

          # Data Fetching

          RESULT_MAP = T.let({
            "pass" => ["allowed"],
            "fail" => %w[failed git_error enter_queue_failed],
            "bypass" => ["bypassed"],
          }.freeze, T::Hash[String, T::Array[String]])

          EVALUATE_RESULT_MAP = T.let(
            RESULT_MAP.merge({ "fail" => ["failed"] }).freeze,
            T::Hash[String, T::Array[String]],
          )

          sig do
            params(counts_by_date: T::Hash[T.untyped, Integer], from: Time, to: Time)
            .returns(T::Array[[String, Integer]])
          end
          def fill_the_gaps(counts_by_date, from, to)
            all_dates = from.to_date.upto(to.to_date)
            all_dates.map do |date|
              [date.to_s, counts_by_date[date] || 0]
            end
          end

          # Returns T.untyped since RuleEngine::RuleSuite scopes like source_result_exists
          # don't exist on ActiveRecord::Relation and PrivateRelation shouldn't be referenced directly.
          sig { returns(T.untyped) }
          def rule_suite_query_by_source
            sql = if @source.is_a?(Organization)
              RuleEngine::RuleSuite
                .where(owner: @source)
            elsif @source.is_a?(Business)
              RuleEngine::RuleSuite
                .where(business: @source)
            else
              RuleEngine::RuleSuite
                .where(repository: @source)
            end

            sql = sql.for_ruleset(@ruleset) if @ruleset.present?

            sql = sql.where(ref_name: "refs/heads/#{@branch}") if @branch.present?

            sql
          end

          sig do
            params(sql: T.untyped, rule_status: String)
            .returns(T.untyped)
          end
          def apply_status_filter(sql, rule_status)
            if @evaluate_status == "evaluate"
              sql.source_result_exists(
                source: @source,
                evaluate_result: T.must(EVALUATE_RESULT_MAP[rule_status]),
              )
            elsif @evaluate_status == "active"
              sql
                .source_result_exists(source: @source, result_not: ["none"])
                .where(result: T.must(RESULT_MAP[rule_status]))
            else # "all" mode: show active and evaluate results
              case rule_status
              when "pass"
                sql.where(result: T.must(RESULT_MAP["pass"]))
                  .source_result_exists(source: @source, result_not: ["none"]).or(
                    sql.where(result: T.must(RESULT_MAP["pass"]))
                      .source_result_exists(evaluate_result: %w[allowed none], source: @source)
                  )
              when "fail"
                sql.where(result: T.must(RESULT_MAP["fail"])).or(
                  sql.source_result_exists(evaluate_result: T.must(EVALUATE_RESULT_MAP["fail"]), source: @source)
                )
              when "bypass"
                sql.where(result: T.must(RESULT_MAP["bypass"]))
                  .source_result_not_exists(evaluate_result: T.must(EVALUATE_RESULT_MAP["fail"]), source: @source).or(
                    sql.where.not(result: T.must(RESULT_MAP["fail"]))
                      .source_result_exists(evaluate_result: T.must(EVALUATE_RESULT_MAP["bypass"]), source: @source)
                  )
              else
                sql
              end
            end
          end

          sig do
            params(sql: T.untyped)
            .returns(T.untyped)
          end
          def apply_evaluate_status_base_filter(sql)
            if @evaluate_status == "evaluate"
              sql.source_result_exists(source: @source, evaluate_result_not: ["none"])
            elsif @evaluate_status == "active"
              sql.source_result_exists(source: @source, result_not: ["none"])
            else
              sql
            end
          end

          sig do
            params(
              rule_status: String,
              from: T.nilable(Time),
              to: T.nilable(Time),
            )
            .returns(Integer)
          end
          def rule_suite_count_in_timespan(rule_status:, from: 1.week.ago, to: 0.weeks.ago)
            sql = rule_suite_query_by_source
            sql = sql.where(created_at: from..to)
            sql = apply_status_filter(sql, rule_status)
            sql.count
          end

          sig do
            params(
              rule_status: String,
              from: T.nilable(Time),
              to: T.nilable(Time),
            )
            .returns(T::Array[[String, Integer]])
          end
          def rule_suite_count_in_timespan_by_day(rule_status:, from: 1.week.ago, to: 0.weeks.ago)
            sql = rule_suite_query_by_source
            sql = sql.where(created_at: from..to).order(created_at: :desc)
            sql = apply_status_filter(sql, rule_status)
            counts_by_date = T.cast(
              sql.group("DATE(created_at)").order("DATE(created_at)").count,
              T::Hash[T.untyped, Integer],
            )
            fill_the_gaps(counts_by_date, from, to)
          end

          sig do
            params(
              from: T.nilable(Time),
              to: T.nilable(Time),
            )
            .returns(T::Array[BypassByUser])
          end
          def rule_suite_count_in_timespan_by_actor(from: 1.week.ago, to: 0.weeks.ago)
            sql = rule_suite_query_by_source
            sql = sql.where(created_at: from..to).order(created_at: :desc)
            sql = apply_evaluate_status_base_filter(sql)
            # For bypasses by actor, we need special handling for evaluate mode
            # since bypass info lives in source_results for evaluate-mode suites
            if @evaluate_status == "evaluate"
              sql = sql.source_result_exists(
                source: @source,
                evaluate_result: ["bypassed"],
              )
            elsif @evaluate_status == "active"
              sql = sql.where(result: "bypassed")
            else
              # "all" mode: bypassed active OR bypassed evaluate
              sql = sql.where(result: "bypassed").or(
                sql.source_result_exists(evaluate_result: ["bypassed"], source: @source)
              )
            end
            # need to optimize this to avoid N+1's
            counts_by_actor = sql.group(:actor_id, :actor_type).count.map do |actor, count|
              actor_name = if actor[1] == "User"
                User.find_by(id: actor[0])&.display_login || "Unknown"
              elsif actor[1] == "PublicKey"
                key = PublicKey.find_by(id: actor[0])
                key&.title || key&.verifier&.display_login || "Unknown [key]"
              end
              BypassByUser.new(actor: actor_name, count:)
            end
          end

          class Metric < T::Struct
            const :name, String
            const :value, Integer
            const :isPercentage, T.nilable(T::Boolean), default: false
            const :valueDiffPercentage, T.nilable(Integer)
            const :link, T.nilable({
              href: String,
              displayText: String,
            })
          end

          class BypassByUser < T::Struct
            const :actor, String
            const :count, Integer
          end

          private

          sig do
            type_parameters(:ReturnType)
              .params(
                query_type: String,
                block: T.proc.returns(T.type_parameter(:ReturnType)),
              )
              .returns(T.type_parameter(:ReturnType))
          end
          def with_query_telemetry(query_type, &block)
            GitHub.dogstats.distribution_time(
              "rules_insights.query.dist.time",
              tags: query_telemetry_tags(query_type),
            ) do
              block.call
            end
          end

          sig { params(query_type: String).returns(T::Array[String]) }
          def query_telemetry_tags(query_type)
            [
              "source:#{@source.class.name&.downcase}",
              "query_type:#{query_type}",
              "evaluate_status:#{@evaluate_status}",
              "has_branch_filter:#{@branch.present?}",
              "has_ruleset_filter:#{@ruleset.present?}",
              "flagged_source:#{FeatureFlag.vexi.enabled?(:rules_insights_profile_specific_sources, @source, default: false)}",
            ]
          end
        end

        class LayoutRoutePayload < ::ReactPayload::Base
          sig { override.returns(String) }
          def route_id
            "layoutRoute"
          end

          sig { void }
          def initialize; end

          sig { override.returns(T::Hash[String, T.untyped]) }
          def payload
            {}
          end
        end

        class OrgDashboardRoutePayload < DashboardRoutePayload
          sig { override.returns(String) }
          def route_id
            "orgDashboardRoute"
          end
        end

        class OrgLayoutRoutePayload < LayoutRoutePayload
          sig { override.returns(String) }
          def route_id
            "orgLayoutRoute"
          end
        end
      end
    end
  end
end
