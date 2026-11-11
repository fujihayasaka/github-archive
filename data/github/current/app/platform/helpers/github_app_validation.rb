# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module GitHubAppValidation

      extend T::Helpers

      requires_ancestor { Platform::Mutations::Base }

      def allowed_to_modify_app?(app_id:)
        if context[:viewer].respond_to?(:installation)
          context[:integration].id == app_id
        elsif context[:viewer].using_auth_via_integration?
          context[:viewer].oauth_access.application_id == app_id
        else
          true
        end
      end
    end
  end
end
