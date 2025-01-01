# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class App < Platform::Objects::Base
      model_name "Integration"
      description "A GitHub App."

      implements_node templates: [[:ua, :user_id, :app_id], [:oa, :org_id, :app_id], [:da, :dotcom_owner_id, :app_id]], as: "A", ready_date: "2021-06-25" do |app|
        app.async_owner.then do |owner|
          if ProximaAppSynchronization.synchronized_third_party?(app)
            Platform::Loaders::ActiveRecordAssociation.load(app, :dotcom_app_owner_metadata).then do |metadata|
              {
                prefix: :da,
                dotcom_owner_id: metadata.dotcom_id,
                app_id: app.id
              }
            end
          elsif app.user_owned?
            {
              prefix: :ua,
              user_id: app.owner_id,
              app_id: app.id
            }
          elsif app.organization_owned?
            {
              prefix: :oa,
              org_id: app.owner_id,
              app_id: app.id
            }
          else
            raise Platform::Errors::Internal, "Unexpected integration owner: #{owner.inspect}"
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      # Ability check for an Integration object
      def self.async_viewer_can_see?(permission, object)
        object.async_readable_by?(permission.viewer).then do |is_readable|
          next true if is_readable
          next false unless permission.viewer

          # App is listed in the Marketplace and the user can manage Marketplace listings
          object.async_marketplace_listing.then do |marketplace_listing|
            next false unless marketplace_listing
            permission.viewer.can_admin_marketplace_listings?
          end
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, integration)
        integration.async_owner.then do |owner|
          org = owner.is_a?(::Organization) ? owner : nil

          bypass_cap_policies = []

          if !GitHub.multi_tenant_enterprise?
            if permission.viewer.try(:can_have_granular_permissions?)
              permission.viewer.ability_delegate.async_target.then do |user_or_org|
                user_or_org.async_business.then do |business|
                  if business && GitHub.flipper[:allow_protected_branch_push_apps].enabled?(business)
                    bypass_cap_policies = [:emu_ownership]
                  end
                end
              end
            end
          end

          permission.access_allowed?(:github_app_viewer,
            resource: integration,
            current_org: org,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            installation_required: false,
            # In order to keep the nice messaging that GraphQL has
            # provided we are enabling or disabling OAP here
            # instead of turning it off entirely and leaning on
            # the access control.
            enforce_oauth_app_policy: integration.private?,
            # Skip enforcing OAP for reading public integrations (GH Apps) in the context of
            # a mutation to avoid issues like:
            # https://github.com/github/ecosystem-apps/issues/3337
            allow_mutation_on_public_resource: !integration.private?,
            # integrations that are not EMU owned can be assigned to push to protected branches
            # but there is no other way in the graphql API to mutate them
            # so we need to allow them to be accessed and skip this policy
            bypass_cap_policies: bypass_cap_policies
          )
        end
      end

      scopeless_tokens_as_minimum

      implements Interfaces::FeatureFlaggable

      implements Interfaces::MarketplaceIntegratable

      created_at_field

      updated_at_field

      database_id_field

      field :name, String, "The name of the app.", null: false

      field :client_id, String, "The client ID of the app.", null: true, method: :key

      field :description, String, "The description of the app.", null: true

      field :description_html, Scalars::HTML, description: "The app's description rendered to HTML.", visibility: :internal, null: true do
        argument :truncate, Integer, "Truncate the description at the specified length", required: false
      end

      def description_html(truncate: nil)
        Platform::Helpers::AppContent.html_for(
          @object, :description, { current_user: @context[:viewer] }, truncate: truncate
        )
      end

      field :short_description_html, Scalars::HTML, description: "A shortened version of the app's description rendered to HTML.", visibility: :internal, null: true do
        argument :truncate, Integer, "Truncate the description at the specified length", required: true
      end

      def short_description_html(truncate:)
        # Try to break at the end of the first sentence
        sentence_break = @object.description.index(/\.\s+/)
        if sentence_break.present? && sentence_break <= truncate
          short_description = @object.description[0..sentence_break]
          truncate = nil
        else
          short_description = @object.description
        end

        rendered_description = Platform::Helpers::AppContent.html_for(
          @object, :short_description, { current_user: @context[:viewer] }, truncate: truncate, value: short_description
        )
      end

      field :slug, String, "A slug based on the name of the app for use in URLs.", null: false

      field :url, Scalars::URI, "The URL to the app's homepage.", null: false

      field :marketplace_listing, Objects::MarketplaceListing, method: :async_marketplace_listing,
        description: "The Marketplace Listing for this App", null: true, visibility: :under_development

      field :logo_url, Scalars::URI, description: "A URL pointing to the app's logo.", null: false do
        argument :size, Integer, "The size of the resulting image.", required: false
      end

      def logo_url(size: nil)
        if GitHub.private_mode_enabled? && Apps::Internal.capable?(:enterprise_avatar_display, app: context[:oauth_app])
          "#{GitHub.api_url}/enterprise/avatars#{@object.primary_avatar_path}?s=#{size}"
        else
          @object.async_owner.then { @object.preferred_avatar_url(size: size) }
        end
      end

      field :logo_background_color, String, "The hex color code, without the leading '#', for the logo background.", method: :bgcolor, null: false

      field :owner, Unions::AppOwner, description: "The owner of this app.", null: false
      def owner
        if ProximaAppSynchronization.synchronized_third_party?(@object)
          Promise.resolve(::DotcomAppOwnerMetadata.find_by(local_app: @object))
        else
          @object.async_owner
        end
      end

      url_fields description: "The HTTP URL for this app", prefix: "html", visibility: :internal do |app|
        app.public_app_path
      end

      field :installed_repositories, Connections.define(Objects::Repository), visibility: :internal, description: "The repositories this app is installed on for a specified account", null: false do
        argument :account, String, "The target account's login.", required: true
      end

      def installed_repositories(**arguments)
        Platform::Loaders::ActiveRecord.load(::User, arguments[:account], column: :login, case_sensitive: false).then do |account|

          next ArrayWrapper.new([]) unless account

          installation = T.let(nil, T.nilable(::IntegrationInstallation))

          if GitHub.flipper[:app_installed_repositories_graphql_filter].enabled?
            installation = ::IntegrationInstallation
              .includes(integration: [owner: :business], target: :business)
              .find_by(integration_id: @object.id, target: account)

            # Avoid leaking repository existence to unauthorized users
            next ArrayWrapper.new([]) unless installation&.viewable_by?(context[:viewer])
          else
            # If we are ever going to include installations for apps that are
            # per-repo install required, we'll need to update this to count the
            # repositories associated to _all_ installations instead of just the
            # one
            installation = ::IntegrationInstallation.find_by(integration_id: @object.id, target_id: account.id, target_type: account.class.base_class)

            next ArrayWrapper.new([]) unless installation
          end

          installation.repositories.filter_spam_and_disabled_for(context[:viewer])
        end
      end

      field :default_permissions, [Objects::AppPermission], description: "The permissions requested by this app on installation", visibility: :under_development, null: false

      def default_permissions
        @object.async_default_permissions.then do |default_permissions|
          default_permissions.to_a.map do |resource, access|
            { resource: resource, access: access.to_s }
          end
        end
      end

      field :default_events, [String], method: :async_default_events, description: "The webhook events this app subscribes to", visibility: :under_development, null: false

      field :ip_allow_list_entries, Connections.define(Objects::IpAllowListEntry),
        description: "The IP addresses of the app.",
        connection: true, null: false do
        argument :order_by, Inputs::IpAllowListEntryOrder,
          "Ordering options for IP allow list entries returned.",
          required: false, default_value: { field: "allow_list_value", direction: "ASC" }
      end

      def ip_allow_list_entries(order_by: nil)
        unless object.ip_allowlist_manageable_by?(context[:viewer])
          raise Errors::Forbidden.new \
            "#{context[:viewer].display_login} does not have the right permission to retrieve ipAllowListEntries."
        end

        entries = ::IpAllowlistEntry.usable_for(object)
        unless order_by.nil?
          entries = entries.order "#{order_by[:field]} #{order_by[:direction]}"
        end

        entries
      end
    end
  end
end
