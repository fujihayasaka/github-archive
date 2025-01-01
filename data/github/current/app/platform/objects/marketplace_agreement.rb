# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarketplaceAgreement < Platform::Objects::Base
      model_name "Marketplace::Agreement"
      description "A legal agreement for the GitHub Marketplace."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for a Marketplace::Agreement object
      def self.async_viewer_can_see?(permission, object)
        permission.viewer.present? # authenticated users can read a Marketplace agreement
      end

      visibility :internal

      minimum_accepted_scopes ["repo"]

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the MarketplaceAgreement object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field(visibility: :internal)
      field :name, String, "The name of this agreement.", null: false
      created_at_field
      field :version, String, "The version of this agreement.", null: false

      field :signatory_type, String, description: "Who is the intended audience for this agreement?", null: false

      def signatory_type
        @object.signatory_type.humanize
      end

      field :body_html, Scalars::HTML, description: "The text of the agreement rendered to HTML.", null: false

      def body_html
        Platform::Helpers::MarketplaceListingContent.html_for(
          @object, :body, { current_user: @context[:viewer] }
        )
      end

      field :signature, Objects::MarketplaceAgreementSignature, description: "Returns the most recent signature for the current user for this agreement.", null: true do
        T.bind(self, GraphQL::Schema::Member::HasArguments)
        argument :organizationID, ID, "ID of the organization on whose behalf the agreement was signed.", required: false,
          as: :organization_id
      end

      def signature(**arguments)
        signatures = @object.signatures.for_user(@context[:viewer])

        if @object.integrator? && arguments[:organization_id]
          org = Helpers::NodeIdentification.
            typed_object_from_id([Objects::Organization], arguments[:organization_id], @context)
          signatures = signatures.for_org(org)
        end

        signatures.latest.first
      end
    end
  end
end
