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

            rulesets = Repositories.domain.rulesets.load_rulesets(@source, include_inherited: false, targets: %w[branch tag push repository])

            @ruleset = T.let(
              filter[:ruleset_name].present? ? rulesets.find { |rs| rs.name == filter[:ruleset_name] } : nil,
              T.nilable(RuleEngine::IRuleset),
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
            @rulesets = T.let(rulesets, T::Enumerable[RuleEngine::IRuleset])
            created_filter = filter[:created]
            @created = T.let(
              created_filter.is_a?(String) ? created_filter : ">@today-1w",
              String,
            )
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

            begin
              result = if cosmos_reads_enabled?
                build_cosmos_payload(filter_hash)
              else
                GitHub::Timer.timeout(RuleEngine::RuleSettingsDependency::RULE_SUITE_TIMEOUT) do
                  build_mysql_payload(filter_hash)
                end
              end
            rescue GitHub::Timer::Error, RuleEngine::RuleSettingsDependency::RuleInsightsTimeoutError, RulesInsights::TwirpError
              result = {
                sourceType: source_type,
                filter: filter_hash,
                rulesets: @rulesets.map { |rs| { name: rs.name } },
                ruleSuites: [],
                metrics: [],
                bypassesByActor: [],
                timedOut: true,
              }
            end

            result[:branchIsValid] = @branch_is_valid unless @branch_is_valid.nil?
            if @source.is_a?(Repository)
              result[:source] = {
                ownerLogin: @source.owner_display_login,
                name: @source.name,
              }
            end
            if @source.is_a?(Organization)
              if cosmos_reads_enabled?
                result[:bypassesByRepo] = result[:bypassesByRepo] || []
              elsif result[:timedOut]
                result[:bypassesByRepo] = []
              else
                begin
                  GitHub::Timer.timeout(RuleEngine::RuleSettingsDependency::RULE_SUITE_TIMEOUT) do
                    result[:bypassesByRepo] = with_query_telemetry("count_bypasses_by_repo") do
                      bypass_count_by_repo
                    end
                  end
                rescue GitHub::Timer::Error, RuleEngine::RuleSettingsDependency::RuleInsightsTimeoutError
                  result[:bypassesByRepo] = []
                  result[:timedOut] = true
                end
              end
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

          sig do
            params(counts_by_date: T::Hash[T.untyped, Integer], all_dates: T::Range[Date])
            .returns(T::Array[[String, Integer]])
          end
          def fill_the_gaps(counts_by_date, all_dates)
            all_dates.map do |date|
              [date.to_s, counts_by_date[date] || 0]
            end
          end

          sig { params(rule_status: String, skip_participation_filter: T::Boolean).returns(T.untyped) }
          def fetch_dashboard_rule_suites(rule_status:, skip_participation_filter: false)
            @source.fetch_rule_suites(
              rule_status: rule_status, evaluate_status: @evaluate_status, ruleset: @ruleset, ref: @branch,
              created: @created, is_ui: true, for_dashboard: true,
              skip_participation_filter: skip_participation_filter,
              user_timezone: @user.time_zone,
            )
          end

          sig { params(rule_status: String).returns(Integer) }
          def rule_suite_count_in_timespan(rule_status:)
            sql, _date_range = fetch_dashboard_rule_suites(rule_status: rule_status)
            sql.count
          end

          sig { params(rule_status: String).returns(T::Array[[String, Integer]]) }
          def rule_suite_count_in_timespan_by_day(rule_status:)
            sql, date_range = fetch_dashboard_rule_suites(rule_status: rule_status)
            counts_by_date = T.cast(
              sql.group("DATE(created_at)").order("DATE(created_at)").count,
              T::Hash[T.untyped, Integer],
            )
            fill_the_gaps(counts_by_date, date_range)
          end

          sig { params(rule_status: String).returns(T.nilable(T::Array[CategoryCount])) }
          def ruleset_counts_in_timespan(rule_status:)
            return nil if @ruleset.present?
            suites, date_range = fetch_dashboard_rule_suites(rule_status:)
            all_rule_runs = suites.flat_map(&:rule_runs)
            GitHub::PrefillAssociations.prefill_batch_method(all_rule_runs, :source_ruleset)
            all_rule_runs.map { |rr| [rr.source_ruleset.name, rr.source_ruleset.source_type] }.tally.map do |ruleset, count|
              name = ruleset[0]
              source_type = if ruleset[1] == "User"
                "organization"
              else
                ruleset[1].downcase
              end
              CategoryCount.new(name:, count:, sourceType: source_type)
            end
          end

          sig { params(rule_status: String).returns(T.nilable(T::Array[CategoryCount])) }
          def rule_counts_in_timespan(rule_status:)
            return nil unless @ruleset.present?
            suites, date_range = fetch_dashboard_rule_suites(rule_status:)
            all_rule_runs = suites.flat_map(&:rule_runs)
            all_rule_runs.map { |rr| rr.rule_type }.tally.map do |rule_type, count|
              name = T.must(Repositories.domain.rulesets.registry.rule_impl_for_rule_type(rule_type)).display_name
              CategoryCount.new(name:, count:)
            end
          end

          sig { returns(T::Array[BypassByUser]) }
          def bypass_count_by_actor
            sql, _date_range = fetch_dashboard_rule_suites(rule_status: "bypass")
            raw = sql.group(:actor_id, :actor_type).count.map do |(actor_id, actor_type), count|
              { actor_id: actor_id, actor_type: actor_type, count: count }
            end
            resolve_bypass_actors(raw)
          end

          sig { returns(T::Array[BypassByRepo]) }
          def bypass_count_by_repo
            # Skip the participation filter — count bypasses by repo regardless of
            # whether org-level rules were involved in the suite.
            sql, _date_range = fetch_dashboard_rule_suites(rule_status: "bypass", skip_participation_filter: true)

            top_counts = sql
              .group(:repository_id)
              .order(Arel.sql("COUNT(*) DESC, repository_id ASC"))
              .limit(10)
              .count

            raw = top_counts.map do |repo_id, count|
              { repo_id: repo_id, count: count }
            end
            resolve_bypass_repos(raw)
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

          class BypassByRepo < T::Struct
            const :repoName, String
            const :ownerLogin, String
            const :count, Integer
          end

          sig { returns(T::Boolean) }
          def cosmos_reads_enabled?
            FeatureFlag.vexi.enabled?(:rules_insights_cosmos_reads, @source, default: false) ||
              @user.feature_flag_enabled?(:rules_insights_cosmos_reads, default: false)
          end

          sig { params(filter_hash: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
          def build_cosmos_payload(filter_hash)
            period = resolve_period
            filters = RulesInsights::Domain::Filters.new(
              evaluate_status: @evaluate_status.to_sym,
              ref: @branch,
              ruleset_id: @ruleset&.id,
            )

            stats = RulesInsights::Domain.new.get_dashboard_stats(
              source: @source,
              period: period,
              filters: filters,
            )

            summary = stats[:summary] || {}
            timeseries = stats[:timeseries] || []

            {
              sourceType: source_type,
              filter: filter_hash,
              rulesets: @rulesets.map { |rs| { name: rs.name } },
              ruleSuites: [
                { name: "Passes", data: timeseries.map { |pt| [pt[:date], pt[:pass] || 0] } },
                { name: "Failures", data: timeseries.map { |pt| [pt[:date], pt[:fail] || 0] } },
                { name: "Bypasses", data: timeseries.map { |pt| [pt[:date], pt[:bypass] || 0] } },
              ],
              metrics: [
                Metric.new(
                  name: "Allowed",
                  value: summary[:pass] || 0,
                  link: { displayText: "View allowed runs", href: @allowed_insights_url },
                ),
                Metric.new(
                  name: "Failed",
                  value: summary[:fail] || 0,
                  link: { displayText: "View failed runs", href: @failed_insights_url },
                ),
                Metric.new(
                  name: "Bypassed",
                  value: summary[:bypass] || 0,
                  link: { displayText: "View bypassed runs", href: @bypassed_insights_url },
                ),
              ],
              bypassesByActor: resolve_bypass_actors(stats[:bypasses_by_actor] || []),
              bypassesByRepo: resolve_bypass_repos(stats[:bypasses_by_repo] || []),
            }
          end

          sig { params(filter_hash: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
          def build_mysql_payload(filter_hash)
            {
              sourceType: source_type,
              filter: filter_hash,
              rulesets: @rulesets.map { |rs| { name: rs.name } },
              ruleSuites: [{
                name: "Passes",
                data: with_query_telemetry("count_by_day_pass") do
                  rule_suite_count_in_timespan_by_day(rule_status: "pass")
                end,
              }, {
                name: "Failures",
                data: with_query_telemetry("count_by_day_fail") do
                  rule_suite_count_in_timespan_by_day(rule_status: "fail")
                end,
              }, {
                name: "Bypasses",
                data: with_query_telemetry("count_by_day_bypass") do
                  rule_suite_count_in_timespan_by_day(rule_status: "bypass")
                end,
              }],
              failuresByRuleset: if @source.feature_enabled_for_source?(:insights_dashboard_ruleset_failures)
                                   with_query_telemetry("count_ruleset_fail") do
                                     ruleset_counts_in_timespan(rule_status: "fail")
                                   end
                                 end,
              failuresByRule: if @source.feature_enabled_for_source?(:insights_dashboard_rule_failures)
                                with_query_telemetry("count_rule_fail") do
                                  rule_counts_in_timespan(rule_status: "fail")
                                end
                              end,
              metrics: [
                Metric.new(
                  name: "Allowed",
                  value: with_query_telemetry("count_by_status_pass") do
                    rule_suite_count_in_timespan(rule_status: "pass")
                  end,
                  link: {
                    displayText: "View allowed runs",
                    href: @allowed_insights_url,
                  },
                ),
                Metric.new(
                  name: "Failed",
                  value: with_query_telemetry("count_by_status_fail") do
                    rule_suite_count_in_timespan(rule_status: "fail")
                  end,
                  link: {
                    displayText: "View failed runs",
                    href: @failed_insights_url,
                  },
                ),
                Metric.new(
                  name: "Bypassed",
                  value: with_query_telemetry("count_by_status_bypass") do
                    rule_suite_count_in_timespan(rule_status: "bypass")
                  end,
                  link: {
                    displayText: "View bypassed runs",
                    href: @bypassed_insights_url,
                  },
                ),
              ],
              bypassesByActor: with_query_telemetry("count_bypasses_by_actor") do
                bypass_count_by_actor
              end,
            }
          end

          sig { returns(RulesInsights::Domain::Period) }
          def resolve_period
            timezone = FeatureFlag.vexi.enabled?(:rule_insights_utc, @user, default: false) ? ActiveSupport::TimeZone.new("UTC") : @user.time_zone
            time_range = Repos::Rules::CreatedDateFilter.resolve_dashboard_date_range(
              @created, timezone: timezone,
              max_lookback_days: RuleEngine::RuleSettingsDependency::MAX_LOOKBACK_DAYS,
            )

            RulesInsights::Domain::Period.new(
              from: time_range.begin,
              to: time_range.end,
            )
          end

          sig { params(actors: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[BypassByUser]) }
          def resolve_bypass_actors(actors)
            # TODO: optimize to avoid N+1's
            actors.filter_map do |entry|
              actor_name = if entry[:actor_type] == "User"
                User.find_by(id: entry[:actor_id])&.display_login || "Unknown"
              elsif entry[:actor_type] == "PublicKey"
                key = PublicKey.find_by(id: entry[:actor_id])
                key&.title || key&.verifier&.display_login || "Unknown [key]"
              end
              next unless actor_name

              BypassByUser.new(actor: actor_name, count: entry[:count] || 0)
            end
          end

          sig { params(repos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[BypassByRepo]) }
          def resolve_bypass_repos(repos)
            repos_by_id = Repository.where(id: repos.map { |r| r[:repo_id] }).index_by(&:id)
            repos.filter_map do |entry|
              repo = repos_by_id[entry[:repo_id]]
              next unless repo

              BypassByRepo.new(repoName: repo.name, ownerLogin: repo.owner_display_login, count: entry[:count] || 0)
            end
          end

          class CategoryCount < T::Struct
            const :name, String
            const :count, Integer
            const :sourceType, T.nilable(String)
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
