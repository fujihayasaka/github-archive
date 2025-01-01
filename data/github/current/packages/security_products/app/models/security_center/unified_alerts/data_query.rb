# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module UnifiedAlerts
    class DataQuery
      extend T::Sig
      extend T::Helpers
      include GitHub::Memoizer
      abstract!

      QueryParser = ::Search::Queries::SecurityCenter::QueryParser
      SOA = ::SecurityOverviewAnalytics
      SOAFilters = SOA::Filters
      SOFilters = ::SecurityCenter::Filters

      AlertRevisionModel = T.type_alias do
        T.any(
          T.class_of(SOA::DependabotAlertRevision),
          T.class_of(SOA::CodeScanningAlertRevision),
          T.class_of(SOA::SecretScanningAlertRevision)
        )
      end

      SECURITY_FEATURE_MODEL_MAPPINGS = T.let({
        SecurityFeatures::DEPENDABOT_ALERTS => SOA::DependabotAlertRevision,
        SecurityFeatures::CODE_SCANNING => SOA::CodeScanningAlertRevision,
        SecurityFeatures::SECRET_SCANNING => SOA::SecretScanningAlertRevision
      }, T::Hash[String, AlertRevisionModel])

      sig do
        params(
          organization: Organization,
          user: User,
          user_session: T.nilable(UserSession),
          tools: T::Array[String],
          query: QueryParser
        ).returns(T.attached_class)
      end
      def self.for_organization(organization, user:, user_session:, tools:, query:)
        new(scope: organization, user:, user_session:, tools:, query:)
      end

      private_class_method :new

      sig { returns(::Organization) }; attr_reader :scope
      sig { returns(::User) }; attr_reader :user
      sig { returns(T.nilable(::UserSession)) }; attr_reader :user_session
      sig { returns(T::Set[String]) }; attr_reader :tools
      sig { returns(QueryParser) }; attr_reader :query

      sig do
        params(
          scope: ::Organization,
          user: ::User,
          user_session: T.nilable(::UserSession),
          tools: T::Array[String],
          query: QueryParser
        ).void
      end
      def initialize(scope:, user:, user_session:, tools:, query:)
        @scope = scope
        @user = user
        @user_session = user_session
        @tools = T.let(tools.to_set, T::Set[String])
        @query = query
      end

      private

      sig { params(feature: String).returns(T.nilable(ActiveRecord::Relation)) }
      def security_feature_base_rel(feature)
        return unless should_run?(feature)

        feature_module = SECURITY_FEATURE_MODEL_MAPPINGS[feature]
        return unless feature_module.present?

        repo_scope_rel = SOA::Repository
          .with_feature_status(feature, status_enabled: true)
          .where(owner_id: scope.id)
          .then do |rel|
            repo_metadata_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end

        feature_module
          .where(repository_id: repo_scope_rel.select(:repository_id))
          .where(next_revision_date_id: SOA::Date::FUTURE_DATE_ID)
          .then do |rel|
            next rel unless feature == SecurityFeatures::DEPENDABOT_ALERTS
            # Dependabot alert specific filters
            dependabot_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
          .then do |rel|
            next rel unless feature == SecurityFeatures::CODE_SCANNING
            # Code scanning specific filters
            rel.where(tool: tools).then do |cs_rel|
              code_scanning_alert_filters.reduce(cs_rel) { |r, filter| filter.apply(r) }
            end
          end
          .then do |rel|
            next rel unless feature == SecurityFeatures::SECRET_SCANNING
            # Secret scanning specific filters
            secret_scanning_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
          .then do |rel|
            shared_alert_filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
      end

      sig { params(feature: String).returns(T::Boolean) }
      def should_run?(feature)
        if feature == SecurityFeatures::DEPENDABOT_ALERTS
          return tools.include?(feature) && !(secret_scanning_filters_applied? || code_scanning_filters_applied?)
        end

        if feature == SecurityFeatures::CODE_SCANNING
          code_scanning_tools = tools - [SecurityFeatures::SECRET_SCANNING, SecurityFeatures::DEPENDABOT_ALERTS]
          return code_scanning_tools.length > 0 && !(secret_scanning_filters_applied? || dependabot_filters_applied?)
        end

        if feature == SecurityFeatures::SECRET_SCANNING
          return tools.include?(feature) && !(code_scanning_filters_applied? || dependabot_filters_applied?)
        end

        false
      end

      sig { returns(T::Array[String]) }
      memoize def security_features
        SecurityFeatures.visible_features(scope)
      end

      sig do
        returns(T::Array[T.any(
          SOAFilters::Filter,
          SOFilters::ByCustomProperty
        )])
      end
      memoize def repo_metadata_filters
        [
          SOAFilters::ByArchived.new(*query.get_positive_and_negative_qualified_values("archived")),
          SOFilters::ByCustomProperty.new(query: query.custom_properties_string, org: scope, user:, user_session:),
          SOAFilters::ByRepository.new(query.get_unqualified_values, [], substring_match: true, scope: scope),
          SOAFilters::ByRepository.new(*query.get_positive_and_negative_qualified_values("repo"), substring_match: false, scope: scope),
          SOAFilters::ByTeam.new(*query.get_positive_and_negative_qualified_values("team"), organizations: [scope], user:),
          SOAFilters::ByTopic.new(*query.get_positive_and_negative_qualified_values("topic"), organizations: [scope]),
          SOAFilters::ByVisibility.new(*query.get_positive_and_negative_qualified_values("visibility")),
        ]
      end

      sig { returns(T::Array[SOAFilters::Filter]) }
      memoize def shared_alert_filters
        [
          SOAFilters::ByState.new(*query.get_positive_and_negative_qualified_values("is")),
          SOAFilters::BySeverity.new(*query.get_positive_and_negative_qualified_values("severity")),
        ]
      end

      sig { returns(T::Array[SOAFilters::Filter]) }
      memoize def dependabot_filters
        [
          ::SecurityOverviewAnalytics::Filters::Dependabot::ByEcosystem.new(*query.get_positive_and_negative_qualified_values(SOA::DependabotAlertRevision::QUALIFIER_ECOSYSTEM)),
          ::SecurityOverviewAnalytics::Filters::Dependabot::ByPackage.new(*query.get_positive_and_negative_qualified_values(SOA::DependabotAlertRevision::QUALIFIER_PACKAGE)),
          ::SecurityOverviewAnalytics::Filters::Dependabot::ByScope.new(*query.get_positive_and_negative_qualified_values(SOA::DependabotAlertRevision::QUALIFIER_SCOPE)),
          ::SecurityOverviewAnalytics::Filters::Dependabot::ByAdvisory.new(*query.get_positive_and_negative_qualified_values(SOA::DependabotAlertRevision::QUALIFIER_ADVISORY)),
        ]
      end

      sig { returns(T::Boolean) }
      memoize def dependabot_filters_applied?
        dependabot_filters.any? { |filter| !filter.is_empty? }
      end

      sig { returns(T::Array[SOAFilters::Filter]) }
      memoize def code_scanning_alert_filters
        rule_filters = SOA::CodeScanningAlertRevision::RuleFilters.new(
          codeql: SOA::Filters::CodeScanning::ByRule.new(*query.get_positive_and_negative_qualified_values(SOA::CodeScanningAlertRevision::QUALIFIER_CODEQL_RULE)),
          third_party: SOA::Filters::CodeScanning::ByRule.new(*query.get_positive_and_negative_qualified_values(SOA::CodeScanningAlertRevision::QUALIFIER_THIRD_PARTY_RULE), codeql_rule: false)
        )

        [
          rule_filters.codeql,
          rule_filters.third_party,
        ]
      end

      sig { returns(T::Boolean) }
      memoize def code_scanning_filters_applied?
        code_scanning_alert_filters.any? { |filter| !filter.is_empty? }
      end

      sig { returns(T::Array[SOAFilters::Filter]) }
      memoize def secret_scanning_filters
        token_filters = SOA::SecretScanningAlertRevision::TokenFilters.new(
          token_type_slug: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByTokenTypeSlug.new(*query.get_positive_and_negative_qualified_values(
            SOA::SecretScanningAlertRevision::QUALIFIER_SECRET_TYPE,
            qualifier_alias: SOA::SecretScanningAlertRevision::QUALIFIER_SECRET_TYPE_ALIAS
          )),
          token_provider: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByTokenProvider.new(*query.get_positive_and_negative_qualified_values(
            SOA::SecretScanningAlertRevision::QUALIFIER_PROVIDER,
            qualifier_alias: SOA::SecretScanningAlertRevision::QUALIFIER_PROVIDER_ALIAS
          )),
          validity: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByValidity.new(*query.get_positive_and_negative_qualified_values(
            SOA::SecretScanningAlertRevision::QUALIFIER_VALIDITY,
            qualifier_alias: SOA::SecretScanningAlertRevision::QUALIFIER_VALIDITY_ALIAS
          )),
          bypassed: ::SecurityOverviewAnalytics::Filters::SecretScanning::ByBypassed.new(*query.get_positive_and_negative_qualified_values(
            SOA::SecretScanningAlertRevision::QUALIFIER_BYPASSED
          ))
        )

        [
          token_filters.token_type_slug,
          token_filters.token_provider,
          token_filters.validity,
          token_filters.bypassed,
        ]
      end

      sig { returns(T::Boolean) }
      memoize def secret_scanning_filters_applied?
        secret_scanning_filters.any? { |filter| !filter.is_empty? }
      end
    end
  end
end
