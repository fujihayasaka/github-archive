# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    class AlertsFilterer
      extend T::Sig
      include GitHub::Memoizer

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      attr_reader :query

      sig { returns(T.any(Organization, Business)) }
      attr_reader :scope

      sig { returns(User) }
      attr_reader :user

      sig { returns(T.nilable(Integer)) }
      attr_reader :slice4

      sig { params(query: ::Search::Queries::SecurityCenter::QueryParser, scope: T.any(Organization, Business), user: User, slice4: T.nilable(Integer)).void }
      def initialize(query:, scope:, user:, slice4: nil)
        @query = query
        @scope = scope
        @user = user
        @slice4 = slice4
      end

      sig { params(security_features: T::Set[String]).returns(ActiveRecord::Relation) }
      def cs_alert_rel(security_features)
        return CodeScanningAlertRevision.none unless should_run_code_scanning_query?

        CodeScanningAlertRevision
          .where(tool: security_features)
          .where.not(alert_severity: nil)
          .then do |rel|
            next rel if slice4.nil?
            rel.where(slice4: slice4)
          end
          .then do |rel|
            alert_centric_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
          .then do |rel|
            code_scanning_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
      end

      sig { returns(ActiveRecord::Relation) }
      def dbot_alert_rel
        return DependabotAlertRevision.none unless should_run_dbot_query?

        DependabotAlertRevision
          .where.not(alert_severity: nil)
          .then do |rel|
            next rel if slice4.nil?
            rel.where(slice4: slice4)
          end
          .then do |rel|
            alert_centric_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
          .then do |rel|
            dependabot_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
      end

      sig { returns(ActiveRecord::Relation) }
      def ss_alert_rel
        return SecretScanningAlertRevision.none unless should_run_secret_scanning_query?

        SecretScanningAlertRevision.all
        .then do |rel|
          next rel if slice4.nil?
          rel.where(slice4: slice4)
        end
        .then do |rel|
          alert_centric_filters.reduce(rel) { |r, filter| filter.apply(r) }
        end
        .then do |rel|
          secret_scanning_filters.reduce(rel) { |r, filter| filter.apply(r) }
        end
      end

      sig { returns(T::Boolean) }
      def alert_centric_filters_applied?
        alert_centric_filters.any? { |filter| !filter.is_empty? }
      end

      sig { returns(T::Boolean) }
      def third_party_rule_filters_applied?
        !code_scanning_rule_filters.third_party.is_empty?
      end

      sig { returns(T::Array[String]) }
      def selected_severities
        ::SecurityOverviewAnalytics::Filters::BySeverity.new(*query.get_positive_and_negative_qualified_values("severity")).selected_filters
      end

      sig { returns(CodeScanningAlertRevision::RuleFilters) }
      def code_scanning_rule_filters
        CodeScanningAlertRevision::RuleFilters.new(
          codeql: ::SecurityOverviewAnalytics::Filters::CodeScanning::ByRule.new(*query.get_positive_and_negative_qualified_values(CodeScanningAlertRevision::QUALIFIER_CODEQL_RULE)),
          third_party: ::SecurityOverviewAnalytics::Filters::CodeScanning::ByRule.new(*query.get_positive_and_negative_qualified_values(CodeScanningAlertRevision::QUALIFIER_THIRD_PARTY_RULE), codeql_rule: false)
        )
      end

      sig { returns(SecretScanningAlertRevision::TokenFilters) }
      def secret_scanning_token_filters
        SecretScanningAlertRevision::TokenFilters.new(
          token_type_slug: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByTokenTypeSlug.new(*query.get_positive_and_negative_qualified_values(
            SecretScanningAlertRevision::QUALIFIER_SECRET_TYPE,
            qualifier_alias: SecretScanningAlertRevision::QUALIFIER_SECRET_TYPE_ALIAS
          )),
          token_provider: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByTokenProvider.new(*query.get_positive_and_negative_qualified_values(
            SecretScanningAlertRevision::QUALIFIER_PROVIDER,
            qualifier_alias: SecretScanningAlertRevision::QUALIFIER_PROVIDER_ALIAS
          )),
          validity: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByValidity.new(*query.get_positive_and_negative_qualified_values(
            SecretScanningAlertRevision::QUALIFIER_VALIDITY,
            qualifier_alias: SecretScanningAlertRevision::QUALIFIER_VALIDITY_ALIAS
          )),
          bypassed: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByBypassed.new(*query.get_positive_and_negative_qualified_values(
            SecretScanningAlertRevision::QUALIFIER_BYPASSED
          ))
        )
      end

      sig { returns(T::Boolean) }
      def should_run_secret_scanning_query?
        !(code_scanning_filters_applied? || dependabot_filters_applied?)
      end

      sig { returns(T::Boolean) }
      def should_run_code_scanning_query?
        !(secret_scanning_filters_applied? || dependabot_filters_applied?)
      end

      sig { returns(T::Boolean) }
      def should_run_dbot_query?
        !(secret_scanning_filters_applied? || code_scanning_filters_applied?)
      end

      private

      sig { params(filter: Symbol).returns(T::Boolean) }
      def should_apply_filter?(filter)
        ::SecurityOverviewAnalytics::FeatureFlagHelper.use_alerts_filterer_class?(filter, scope, user)
      end

      sig { returns(T::Boolean) }
      def secret_scanning_filters_applied?
        secret_scanning_filters.any? { |filter| !filter.is_empty? }
      end

      sig { returns(T::Boolean) }
      def code_scanning_filters_applied?
        code_scanning_filters.any? { |filter| !filter.is_empty? }
      end

      sig { returns(T::Boolean) }
      def dependabot_filters_applied?
        dependabot_filters.any? { |filter| !filter.is_empty? }
      end

      sig { returns(T::Array[T.untyped]) }
      def alert_centric_filters
        filters = []
        filters << ::SecurityOverviewAnalytics::Filters::ByResolution.new(*query.get_positive_and_negative_qualified_values("resolution")) if should_apply_filter?(:resolution)
        filters << ::SecurityOverviewAnalytics::Filters::BySeverity.new(*query.get_positive_and_negative_qualified_values("severity")) if should_apply_filter?(:severity)
        filters
      end

      sig { returns(T::Array[T.untyped]) }
      def secret_scanning_filters
        filters = []

        filters << secret_scanning_token_filters.token_type_slug
        filters << secret_scanning_token_filters.token_provider
        filters << secret_scanning_token_filters.validity
        filters << secret_scanning_token_filters.bypassed

        filters
      end

      sig { returns(T::Array[T.untyped]) }
      def code_scanning_filters
        filters = []

        filters << code_scanning_rule_filters.codeql
        filters << code_scanning_rule_filters.third_party

        filters
      end

      sig { returns(T::Array[T.untyped]) }
      def dependabot_filters
        filters = []

        filters << ::SecurityOverviewAnalytics::Filters::Dependabot::ByEcosystem.new(*query.get_positive_and_negative_qualified_values(DependabotAlertRevision::QUALIFIER_ECOSYSTEM))
        filters << ::SecurityOverviewAnalytics::Filters::Dependabot::ByPackage.new(*query.get_positive_and_negative_qualified_values(DependabotAlertRevision::QUALIFIER_PACKAGE))
        filters << ::SecurityOverviewAnalytics::Filters::Dependabot::ByScope.new(*query.get_positive_and_negative_qualified_values(DependabotAlertRevision::QUALIFIER_SCOPE))

        filters
      end
    end
  end
end
