# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Filters
    module FeatureStatusSummary
      class Filterer
        include GitHub::Memoizer

        sig { params(query: ::Search::Queries::SecurityCenter::QueryParser).void }
        def initialize(query)
          @query = query
        end

        sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
        def apply(rel)
          rel.then { |rel| filters.reduce(rel) { |r, filter| filter.apply(r) } }
        end

        sig { returns T::Array[Filter] }
        memoize def filters
          [
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("advanced-security"), feature: :advanced_security),
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("code-scanning-alerts"), feature: :code_scanning_alerts),
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("code-scanning-pull-request-alerts"), feature: :code_scanning_pr_reviews),
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("code-scanning-default-setup"), feature: :code_scanning_auto_codeql),
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("dependabot-alerts"), feature: :dependabot_alerts),
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("dependabot-security-updates"), feature: :dependabot_security_updates),
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("secret-scanning-alerts"), feature: :secret_scanning_alerts),
            ByFeature.new(*@query.get_positive_and_negative_qualified_values("secret-scanning-push-protection"), feature: :secret_scanning_push_protection),
            ByHasSeverity.new(*@query.get_positive_and_negative_qualified_values("has-severity")),
          ].compact
        end
      end
    end
  end
end
