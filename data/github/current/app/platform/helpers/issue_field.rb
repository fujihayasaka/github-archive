# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    class IssueField
      sig { params(permission: T.untyped, object: T.untyped).returns(::Promise[T::Boolean]) }
      def self.async_api_can_access?(permission, object)

        object.async_owner.then do |owner|
          next false unless owner&.is_a?(::Organization)
          next false unless IssueFieldsFeature.enabled?(owner, actor: permission.viewer)

          permission.access_allowed?(
              :read_issue_fields,
              resource: owner,
              issue_field: object,
              current_org: owner,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
        end
      end

      sig { params(permission: T.untyped, object: T.untyped).returns(::Promise[T::Boolean]) }
      def self.async_viewer_can_see?(permission, object)
        object.async_owner.then do |owner|
          next false unless owner&.is_a?(::Organization)
          next false unless IssueFieldsFeature.enabled?(owner, actor: permission.viewer)

          permission.access_allowed?(
            :read_issue_fields,
            resource: owner,
            issue_field: object,
            current_org: owner,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      sig do
        params(
          issue_fields: T::Array[Issues::IIssueField],
          sort_by: String,
          direction: String,
        ).returns(T::Array[Issues::IIssueField])
      end
      def self.sort(issue_fields, sort_by, direction)
        issue_fields.sort do |a, b|
          # Get the values to compare based on the field that is going to be sorted
          value_a = extract_sort_value(a, sort_by)
          value_b = extract_sort_value(b, sort_by)

          comparison = case sort_by.downcase
          when "name"
            # When sort by is name, both values are expected to be strings
            string_a = T.cast(value_a, String)
            string_b = T.cast(value_b, String)
            string_a <=> string_b
          when "created_at"
            # When sort by is created_at, both values are expected to be timestamps
            int_a = T.cast(value_a, Integer)
            int_b = T.cast(value_b, Integer)
            int_a <=> int_b
          end
          if comparison.nil?
            0
          else
            direction.downcase == "desc" ? -comparison : comparison
          end
        end
      end

      sig { params(issue_field: Issues::IIssueField, sort_by: String).returns(T.any(String, Integer)) }
      def self.extract_sort_value(issue_field, sort_by)
        case sort_by.downcase
        when "name"
          issue_field.name
        when "created_at"
          issue_field.created_at.to_i
        end
      end
    end
  end
end
