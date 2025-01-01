# typed: true
# frozen_string_literal: true
module Platform
  module Objects
    class MarketplaceAgreementSignature < Platform::Objects::Base
      model_name = "Marketplace::AgreementSignature"
      description "A signature for the Marketplace Agreement by a particular user."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::AgreementSignature object
      def self.async_viewer_can_see?(permission, object)
        object.async_signatory.then do |signatory|
          next true if signatory == permission.viewer

          object.async_organization.then do |organization|
            (organization ? organization.async_adminable_by?(permission.viewer) : Promise.resolve(false)).then do |is_adminable|
              is_adminable || permission.viewer.can_admin_marketplace_listings?
            end
          end
        end
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      created_at_field

      field :agreement, Objects::MarketplaceAgreement,
        method: :async_agreement,
        description: "Returns the agreement that was signed.",
        null: false

      field :organization, Objects::Organization,
        method: :async_organization,
        description: "The organization this signature was signed on behalf of.",
        null: true

      field :signatory, Objects::User,
        method: :async_signatory,
        description: "The user who made this signature.",
        null: true
    end
  end
end
