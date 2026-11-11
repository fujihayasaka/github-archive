# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Conditions
    class RepositoryNameMatcher < SettingsCoreV2::ConditionMatcher
      ATTRIBUTE = "repository.name"

      sig { override.returns(String) }
      def attribute
        ATTRIBUTE
      end

      sig { override.params(resource: T.untyped, sub_type: T.nilable(String)).returns(T.nilable(String)) }
      def effective_value(resource, sub_type = nil)
        return nil unless resource.is_a?(Repository)
        resource.name
      end

      sig { override.params(parent: T.untyped, operation: IConditionExpression::Operation, value: T.any(String, T::Array[String]), sub_type: T.nilable(String)).returns({ count: Integer, total: Integer }) }
      def count_matches(parent, operation, value, sub_type = nil)
        return { count: 0, total: 0 } unless parent.is_a?(Organization)

        repos = parent.repositories
        total = repos.count

        count = case operation
        when IConditionExpression::Operation::EQ, IConditionExpression::Operation::IN
          repos.where(name: value).count
        when IConditionExpression::Operation::NE, IConditionExpression::Operation::NIN
          total - repos.where(name: value).count
        else
          0
        end

        { count:, total: }
      end

      sig { override.params(parent: T.untyped, query: T.nilable(String), limit: Integer).returns(T.untyped) }
      def search(parent, query, limit: 20)
        return [] unless parent.is_a?(Organization)

        repos = if query.present?
          parent.repositories.where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%").limit(limit)
        else
          parent.repositories.limit(limit)
        end

        repos
      end
    end
  end
end
