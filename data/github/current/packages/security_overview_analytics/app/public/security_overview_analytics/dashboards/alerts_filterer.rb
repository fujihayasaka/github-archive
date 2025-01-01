# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    class AlertsFilterer
      include GitHub::Memoizer

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      attr_reader :query

      sig { returns(T.any(Organization, Business)) }
      attr_reader :scope

      sig { returns(User) }
      attr_reader :user

      sig { params(query: ::Search::Queries::SecurityCenter::QueryParser, scope: T.any(Organization, Business), user: User).void }
      def initialize(query:, scope:, user:)
        @query = query
        @scope = scope
        @user = user
      end

      sig { params(security_features: T::Set[String], slice_by: T.nilable(SecurityOverviewAnalytics::Dashboards::Overview::Queries::Base::SliceBy)).returns(ActiveRecord::Relation) }
      def cs_alert_rel(security_features:, slice_by: nil)
        return CodeScanningAlertRevision.none unless should_run_code_scanning_query?

        CodeScanningAlertRevision
          .where(tool: security_features)
          .where.not(alert_severity: nil)
          .then do |rel|
            if slice_by.present?
              if slice_by.dimension == :by_rule
                rel.where(rule_slice4: slice_by.value_4_slices)
              elsif slice_by.dimension == :by_alert_revision
                add_slice_to_rel(rel:, alert_revisions_slice4: slice_by.value_4_slices)
              else
                rel
              end
            else
              rel
            end
          end
          .then do |rel|
            alert_centric_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
          .then do |rel|
            code_scanning_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
      end

      sig { params(slice_by: T.nilable(SecurityOverviewAnalytics::Dashboards::Overview::Queries::Base::SliceBy)).returns(ActiveRecord::Relation) }
      def dbot_alert_rel(slice_by: nil)
        return DependabotAlertRevision.none unless should_run_dbot_query?

        DependabotAlertRevision
          .where.not(alert_severity: nil)
          .then do |rel|
            if slice_by.present?
              if slice_by.dimension == :by_advisory
                rel.where(advisory_slice4: slice_by.value_4_slices)
              elsif slice_by.dimension == :by_alert_revision
                add_slice_to_rel(rel:, alert_revisions_slice4: slice_by.value_4_slices)
              else
                rel
              end
            else
              rel
            end
          end
          .then do |rel|
            alert_centric_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
          .then do |rel|
            dependabot_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
      end

      sig { params(slice_by: T.nilable(SecurityOverviewAnalytics::Dashboards::Overview::Queries::Base::SliceBy)).returns(ActiveRecord::Relation) }
      def ss_alert_rel(slice_by: nil)
        return SecretScanningAlertRevision.none unless should_run_secret_scanning_query?

        SecretScanningAlertRevision.all
        .then do |rel|
          if slice_by.present? && slice_by.dimension == :by_alert_revision
            add_slice_to_rel(rel:, alert_revisions_slice4: slice_by.value_4_slices)
          else
            rel
          end
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

      sig { params(rel: ActiveRecord::Relation, alert_revisions_slice4: T.nilable(Integer)).returns(ActiveRecord::Relation) }
      def add_slice_to_rel(rel:, alert_revisions_slice4:)
        rel.where(slice4: alert_revisions_slice4)
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
        filters << ::SecurityOverviewAnalytics::Filters::BySeverity.new(*query.get_positive_and_negative_qualified_values("severity"))
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
