# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Stafftools
  module Businesses
    class CredentialView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include OauthHelper
      include ApplicationHelper

      attr_reader :credential_authorization

      def initialize(**arguments)
        super(arguments)
        @credential_authorization = arguments[:credential_authorization]
      end

      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def public_key?
        @public_key ||= credential_authorization.credential_type == "PublicKey"
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      def oauth_access?
        !public_key?
      end

      def last_accessed_description
        cutoff = credential_authorization.credential_type.constantize::ACCESS_CUTOFF_DATE

        if credential_authorization.accessed_at
          "Last used within the last #{last_accessed_at_time_ago_in_words(credential_authorization.accessed_at)}"
        else
          if credential_authorization.credential.created_at && credential_authorization.credential.created_at > cutoff
            "Never used"
          else
            desc = "No activity has been logged since token logging began on #{cutoff.strftime('%B %d, %Y')}"
            icon = helpers.content_tag("span", class: "tooltipped tooltipped-s", 'aria-label': desc) do # rubocop:disable Rails/ViewModelHTML
              helpers.octicon("info")
            end
            helpers.safe_join [icon, " No recent activity"]
          end
        end
      end

      def masked_parts
        if public_key?
          credential_authorization.fingerprint
        else
          "#{ "*" * 5 }#{ credential_authorization.credential.token_last_eight }"
        end
      end

      def display_name
        public_key? ? "SSH Key" : "Personal Access Token"
      end

      def read_only_display
        return if oauth_access?
        "— " + (credential_authorization.credential.read_only? ? "Read-only" : "Read/write")
      end

      def scopes_description_tooltip
        return if public_key?
        scopes_description_tooltip_list(credential_authorization.credential.scopes)
      end
    end
  end
end
