# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdatePreferredDiffView < Platform::Mutations::Base
      visibility :internal
      description "Update the preferred diff view for a user"

      minimum_accepted_scopes ["user"]

      argument :preferred_diff_view, String, description: "The user's updated preferred diff view, should be 'split' or 'unified'", required: true

      field :user, Objects::User, description: "The updated user object", null: true

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(:update_user, resource: permission.viewer,
                                   current_repo: nil, current_org: nil,
                                   allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(**inputs)
        viewer = context[:viewer]
        diff_view = inputs[:preferred_diff_view]
        diff_view_sym = diff_view&.to_sym || :unified
        viewer.set_diff_preference(diff_view_sym)
        { user: viewer }
      rescue ArgumentError => e
        raise Errors::Unprocessable.new(e.message)
      end
    end
  end
end
