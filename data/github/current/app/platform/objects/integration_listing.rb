# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IntegrationListing < Platform::Objects::Base
      description "A public description of an Integration."

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
        return true if object.published?
        false
      end

      minimum_accepted_scopes ["repo"]
      visibility :internal

      field :id, Integer, "The internal integration's id.", null: false

      field :name, String, "The integration's full name.", null: false
      field :slug, String, "The integration's short URL name.", null: false
      field :blurb, String, "The integration's short description.", null: false

      field :privacy_policy_url, Scalars::URI, "A link to the integration's privacy policy.", null: false
      field :tos_url, Scalars::URI, "A link to the integration's terms of service.", null: true
      field :company_url, Scalars::URI, "A link to the developer of the integrations website.", null: true
      field :status_url, Scalars::URI, "A link to the integration's status page.", null: true
      field :support_url, Scalars::URI, "A link to the integration's support site", null: true
      field :documentation_url, Scalars::URI, "A link to the integration's documentation.", null: true
      field :pricing_url, Scalars::URI, "A link to the integration's detailed pricing", null: true
      field :body, Scalars::HTML, description: "The integration's rendered description.", method: :body_html, null: false
      field :owner, User, visibility: :internal, description: "The owner of the app represented by this listing.", null: false

      def owner
        @object.async_integration.then do |integration|
          case @object.integration
          when ::Integration
            Loaders::ActiveRecord.load(::User, integration.owner_id)
          when ::OauthApplication
            Loaders::ActiveRecord.load(::User, integration.user_id)
          end
        end
      end

      field :categories, [Objects::IntegrationFeature], visibility: :internal, description: "Get alphabetically sorted list of Integration categories", null: false

      def categories
        @object.features.at_least_visible.order(:name)
      end

      field :marketplace_listing, Objects::MarketplaceListing, visibility: :internal, null: true, description: <<~DESCRIPTION
        Find the approved Marketplace listing for the same app this Integrations listing
        represents, if this Integration listing is published.
      DESCRIPTION

      def marketplace_listing
        if @object.published?
          Marketplace::Listing.publicly_listed.where(listable: @object).first
        end
      end

      field :app, App, description: "The GitHub App this listing represents.", null: true

      def app
        @object.async_integration.then do |_integration|
          if @object.integration.is_a? ::Integration
            @object.integration
          end
        end
      end

      field :oauth_application, Objects::OauthApplication, visibility: :internal, description: "The OAuth application this listing represents.", null: true

      def oauth_application
        @object.async_integration.then do |_integration|
          if @object.integration.is_a? ::OauthApplication
            @object.integration
          end
        end
      end

      field :languages, [String, null: true], visibility: :internal, description: "Get alphabetically sorted list of supported languages", null: false

      def languages
        @object.languages.pluck(:name).sort
      end

      field :avatar_url, Scalars::URI, description: "The integration's short description.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      def avatar_url(**arguments)
        "modules/marketplace/logo-bitrise.png"
      end

      field :avatar_color, String, description: "The integration's short description.", null: false

      def avatar_color
        "#ffffff"
      end

      field :installation_count, Integer, description: "The number of times this integration has been installed.", null: false do
        argument :since, Integer, "Only count installations created after this epoch time", required: false
      end

      def installation_count(**arguments)
        @object.async_integration.then do |_integration|
          case @object.integration
          when ::Integration
            @object.integration.installations.
              since(Time.at(arguments[:since])).count
          when ::OauthApplication
            @object.integration.authorizations.
              where("created_at > ?", Time.at(arguments[:since])).count
          end
        end
      end

      field :integration_type, Enums::IntegrationType, description: "The type of integration that this describes", null: false

      def integration_type
        return "none" if @object.learn_more_url?

        @object.async_integration.then do |_integration|
          case @object.integration
          when ::Integration
            "github_app"
          when ::OauthApplication
            "oauth"
          else
            "none"
          end
        end
      end

      field :integration_installed, Boolean, description: "Whether this integration has been installed for this user", null: false

      def integration_installed
        return false unless current_user = @context[:viewer]

        @object.async_integration.then do |_integration|
          case @object.integration
          when ::Integration
            ::Integrations::SelectTargetView.new(current_user: current_user,
              integration: @object.integration).integration_installed?
          when ::OauthApplication
            # FIXME: this needs to use a loader
            current_user.
              oauth_authorizations.
              exists?(application_id: @object.integration_id)
          end
        end
      end

      field :paid, Boolean, description: "Whether this integration is sold through the marketplace", null: false

      def paid
        false
      end

      url_fields prefix: "installation", description: "The HTTP URL for the installation endpoint" do |integration_listing|
        integration_listing.async_integration.then do |integration|
          case integration
          when ::Integration
            template = Addressable::Template.new("/integrations/{integration}/installations/new")
            template.expand integration: integration_listing.slug
          when ::OauthApplication
            template = Addressable::Template.new("/integrations/{integration}/install")
            template.expand integration: integration_listing.slug
          end
        end
      end

      url_fields prefix: "configuration", description: "The HTTP URL for the configuration endpoint" do |integration_listing|
        integration_listing.async_integration.then do |_integration|
          case integration_listing.integration
          when ::Integration
            template = Addressable::Template.new("/integrations/{integration}/installations/new")
            template.expand integration: integration_listing.slug
          when ::OauthApplication
            template = Addressable::Template.new("/settings/connections/applications/{client_id}")
            template.expand client_id: integration_listing.client_id
          end
        end
      end
    end
  end
end
