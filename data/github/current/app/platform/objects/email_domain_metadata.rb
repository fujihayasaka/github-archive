# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class EmailDomainMetadata < Platform::Objects::Base
      description "Email domain metadata from EmailDomainReputationRecord."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :email_domains, [String], description: "Associated email domains.", null: false

      def email_domains
        @object[:email_domains]
      end

      field :mx_exchanges, [String], description: "Associated MX exchanges.", null: false

      def mx_exchanges
        @object[:mx_exchanges]
      end

      field :a_records, [String], description: "Associated A records.", null: false

      def a_records
        @object[:a_records]
      end

      field :has_valid_public_suffix, Boolean, description: "Does email domain have a valid public suffix?", null: true

      def has_valid_public_suffix
        @object[:has_valid_public_suffix]
      end
    end
  end
end
