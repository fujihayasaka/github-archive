# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Risk
    class ByAccessibleRepos
      extend T::Sig

      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

      sig do
        params(
          repo_ids_by_feature: T.nilable(T::Hash[Symbol, T::Array[Integer]]),
          parser: RiskQueryParser,
        ).void
      end
      def initialize(repo_ids_by_feature:, parser:)
        @repo_ids_by_feature = repo_ids_by_feature
        @parser = parser
      end

      sig { params(rel: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def apply(rel)
        # org owners and security managers aren't subject to repo accessibility restrictions
        return rel if @repo_ids_by_feature.nil?

        rel.where(repository_id: repository_ids)
      end

      sig { returns(T.nilable(T::Array[Integer])) }
      def repository_ids
        # org owners and security managers aren't subject to repo accessibility restrictions
        return nil if @repo_ids_by_feature.nil?

        feature_inclusive_filters = [
            RiskQueryParser::DEPENDABOT_ALERTS,
            RiskQueryParser::CODE_SCANNING,
            RiskQueryParser::SECRET_SCANNING,
          ].
          each_with_object({}) do |qualifier, memo|
            memo[qualifier] = @parser.values_for_qualifier(qualifier).first
          end

        # start with the union of accessible repos for all types
        repo_ids = @repo_ids_by_feature.values.flatten.uniq

        # if we had any "include"-type filters by feature, further limit to just those accessible repos
        if feature_inclusive_filters[RiskQueryParser::DEPENDABOT_ALERTS].any?
          feature_repo_ids = @repo_ids_by_feature[:dependabot_alerts]
          repo_ids &= feature_repo_ids if feature_repo_ids
        end
        if feature_inclusive_filters[RiskQueryParser::CODE_SCANNING].any?
          feature_repo_ids = @repo_ids_by_feature[:code_scanning]
          repo_ids &= feature_repo_ids if feature_repo_ids
        end
        if feature_inclusive_filters[RiskQueryParser::SECRET_SCANNING].any?
          feature_repo_ids = @repo_ids_by_feature[:secret_scanning]
          repo_ids &= feature_repo_ids if feature_repo_ids
        end

        repo_ids
      end


    end
  end
end
