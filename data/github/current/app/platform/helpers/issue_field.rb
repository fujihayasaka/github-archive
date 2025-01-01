# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    class IssueField

      sig { params(permission: T.untyped, issue_field: T.untyped).returns(::Promise[T::Boolean]) }
      def self.async_api_can_access?(permission, issue_field)
        issue_field.async_owner.then do |owner|
          next false unless owner&.is_a?(::Organization)
          next false unless IssueFieldsFeature.enabled?(owner, actor: permission.viewer)

          permission.access_allowed?(
              :read_issue_fields,
              resource: owner,
              issue_field: issue_field,
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
    end
  end
end
