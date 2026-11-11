# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module Conditions
    class OrganizationNameMatcher < ConditionMatcher
      ATTRIBUTE = T.let("organization.name".freeze, String)

      sig { override.returns(String) }
      def attribute
        ATTRIBUTE
      end

      sig { override.params(resource: T.untyped, sub_type: T.nilable(String)).returns(T.nilable(String)) }
      def effective_value(resource, sub_type = nil)
        return nil unless resource.is_a?(Organization)
        resource.display_login
      end

      sig { override.params(parent: T.untyped, operation: IConditionExpression::Operation, value: T.any(String, T::Array[String]), sub_type: T.nilable(String)).returns({ count: Integer, total: Integer }) }
      def count_matches(parent, operation, value, sub_type = nil)
        return { count: 0, total: 0 } if parent.nil?

        orgs = parent.organizations
        total = orgs.count

        org_names = value.is_a?(String) ? [value].compact : value
        count = case operation
        when IConditionExpression::Operation::EQ
          orgs.where(login: org_names.first).count
        when IConditionExpression::Operation::IN
          orgs.where(login: org_names).count
        when IConditionExpression::Operation::NE
          total - orgs.where(login: org_names.first).count
        when IConditionExpression::Operation::NIN
          total - orgs.where(login: org_names).count
        else
          0
        end

        { count:, total: }
      end

      sig { override.params(parent: T.untyped, query: T.nilable(String), limit: Integer).returns(T.untyped) }
      def search(parent, query, limit: 20)
        return [] unless parent

        orgs = if query.present?
          parent.organizations.where("login LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%").limit(limit)
        else
          parent.organizations.limit(limit)
        end

        orgs
      end
    end
  end
end
