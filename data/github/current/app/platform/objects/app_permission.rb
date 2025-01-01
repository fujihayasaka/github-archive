# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AppPermission < Platform::Objects::Base

      description "Permission access for an App"
      visibility :under_development

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for an Integration permission
      #
      # This object is just a hash, not globally indentifiable and it is always queried
      # in the context of an App where the readability by the viewer is already checked.
      def self.async_viewer_can_see?(permission, object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.hidden_from_public?(self) # Update this authorization if we ever go public with this object
      end

      scopeless_tokens_as_minimum

      field :resource, String,                          description: "The type of resource the app has access to",                visibility: :under_development, null: false
      field :access,   Enums::AppPermissionAccessLevel, resolver_method: :access_value, description: "The level of access the app has to the specified resource", visibility: :under_development, null: false

      # This is a workaround for a bug introduced by the graphql-pro gem which add methods with the same name as this field
      def access_value
        object[:access]
      end
    end
  end
end
