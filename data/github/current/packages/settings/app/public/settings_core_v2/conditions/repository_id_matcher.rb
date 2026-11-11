# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Conditions
    class RepositoryIdMatcher < SettingsCoreV2::ConditionMatcher
      ATTRIBUTE = "repository.id"

      sig { override.returns(String) }
      def attribute
        ATTRIBUTE
      end

      sig { override.params(resource: T.untyped, sub_type: T.nilable(String)).returns(T.nilable(String)) }
      def effective_value(resource, sub_type = nil)
        return nil unless resource.is_a?(Repository)
        resource.global_relay_id
      end

      sig { override.params(parent: T.untyped, operation: IConditionExpression::Operation, value: T.any(String, T::Array[String]), sub_type: T.nilable(String)).returns({ count: Integer, total: Integer }) }
      def count_matches(parent, operation, value, sub_type = nil)
        return { count: 0, total: 0 } unless parent.is_a?(Organization)

        total = parent.repositories.count

        ids = value.is_a?(String) ? [value].compact : value
        return { count: 0, total: } if ids.empty?

        repo_db_ids = ids.filter_map do |node_id|
          result = Platform::Helpers::NodeIdentification.from_global_id(node_id)
          next unless result && result[0] == "Repository"
          result[1]
        rescue
          nil
        end

        case operation
        when IConditionExpression::Operation::EQ
          count = parent.repositories.where(id: repo_db_ids.first).count
        when IConditionExpression::Operation::IN
          count = parent.repositories.where(id: repo_db_ids).count
        when IConditionExpression::Operation::NE
          count = parent.repositories.where.not(id: repo_db_ids.first).count
        when IConditionExpression::Operation::NIN
          count = parent.repositories.where.not(id: repo_db_ids).count
        else
          count = 0
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

      sig { override.params(parent: T.untyped, ids: T::Array[String]).returns(T.untyped) }
      def resolve(parent, ids)
        return [] unless parent.is_a?(Organization)
        return [] if ids.empty?

        repo_db_ids = ids.filter_map do |node_id|
          Platform::Helpers::NodeIdentification.from_global_id(node_id)[1]
        rescue
          nil
        end

        return [] if repo_db_ids.empty?

        parent.repositories.where(id: repo_db_ids)
      end
    end
  end
end
