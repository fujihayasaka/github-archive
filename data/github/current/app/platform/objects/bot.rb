# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Bot < Platform::Objects::Base
      docs_category :apps
      description "A special type of user which takes actions on behalf of GitHub Apps."

      key fields: :database_id

      def self.resolve_reference(reference, context)
        database_id = reference.is_a?(Hash) && reference[:database_id].to_i
        if database_id && database_id > 0
          Platform::Loaders::ActiveRecord.load(::Bot, database_id, security_violation_behaviour: :nil)
        else
          Platform::Interfaces::Node.resolve_reference_by_node_id(self, reference, context)
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, bot)
        permission.typed_can_access?("User", bot)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        !object.hide_from_user?(permission.viewer)
      end

      scopeless_tokens_as_minimum

      # this cannot be rolled out until after Actions resolves an issue with decoding
      # the new GlobalID format.  see: https://github.com/github/c2c-actions-experience/issues/3955
      implements_node templates: [[:b, :bot_id]], as: "BOT", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |bot|
        { prefix: :b, bot_id: bot.id }
      end

      implements Interfaces::Actor

      implements Interfaces::UniformResourceLocatable

      database_id_field

      created_at_field
      updated_at_field

      url_fields description: "The HTTP URL for this bot" do |bot|
        bot.permalink(include_host: false)
      end

      field :marketplace_listing_url, Scalars::URI, null: true, visibility: :internal, description: "The Marketplace listing URL for this bot if it has an approved listing. Otherwise, it is just the app URL."

      field :avatar_url, Scalars::URI, description: "A URL pointing to the GitHub App's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      field :app, Objects::App, visibility: :internal, description: "The parent GitHub App", null: false, method: :async_integration

      def avatar_url(size: nil)
        @object.async_integration.then(&:async_owner).then do
          @object.primary_avatar_url(size)
        end
      end

      field :stafftools_info, Objects::BotStafftoolsInfo, visibility: :internal, description: "Bot information only visible to site admin", null: true

      def stafftools_info
        if self.class.viewer_is_site_admin?(context[:viewer], self.class.name)
          Models::AccountStafftoolsInfo.new(@object)
        else
          nil
        end
      end

      def marketplace_listing_url
        @object.async_marketplace_listing_url
      end

      field :is_dependabot, Boolean, visibility: :internal, description: "Whether this bot's parent is the dependabot app", null: false

      def is_dependabot
        return false unless GitHub.dependabot_github_app.present?
        @object.async_integration.then do |integration|
          integration.present? && integration.dependabot_github_app?
        end
      end

      field :is_copilot, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether this bot's parent is a Copilot app", null: false

      def is_copilot
        @object.async_integration.then do |integration|
          integration.present? && Apps::Privileged.capable?(:is_copilot, app: integration)
        end
      end

      field :is_agent, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether this bot is an Agent app or not", null: false

      def is_agent
        @object.async_agentic_app.then do |agent|
          agent.present?
        end
      end

      field :needs_authorization, Boolean, required_capabilities: [:mobile_only_schema_mask], description: "Whether the viewer needs to authorize this bot's agent app before using it.", null: true

      def needs_authorization
        authz_context = agent_authorization_context

        authz_context.then do |authz_info|
          authz_info&.[](:needs_authorization)
        end
      end

      field :authorization_url, Scalars::URI, required_capabilities: [:mobile_only_schema_mask], description: "The URL the viewer can visit to authorize this bot's agent app.", null: true

      def authorization_url
        authz_context = agent_authorization_context

        authz_context.then do |authz_info|
          next nil unless authz_info&.[](:needs_authorization)

          oauth_authorization_url_for_integration(authz_info[:integration])
        end
      end

      field :requires_workflow_approval, Boolean, visibility: :internal, description: "Whether this bot requires workflow approval for Actions events", null: false

      def requires_workflow_approval
        @object.async_integration.then do |integration|
          if FeatureFlag.vexi.enabled?(:actions_use_agentic_app_registry_for_workflow_approval, integration, default: false)
            integration.present? && @object.async_agentic_app.then { |agent| !!agent.presence&.require_workflow_approval_for_prs? }
          else
            integration.present? && Apps::Privileged.capable?(:actions_require_workflow_approval, app: integration)
          end
        end
      end

      private

      # This always returns a Promise so `||=` safely memoizes the nil path too.
      def agent_authorization_context # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
        @_agent_authorization_context ||= begin
          viewer = context[:viewer]
          if !viewer || !FeatureFlag.vexi.enabled?(:copilot_swe_agent_authorization_status, viewer, default: false)
            Promise.resolve(nil)
          else
            @object.async_agentic_app.then do |agent|
              next nil unless agent

              integration = agent.integration
              next nil unless integration

              Platform::Loaders::AgentNeedsAuthorization.load(viewer.id, integration.id).then do |needs_authorization|
                {
                  integration: integration,
                  needs_authorization: needs_authorization,
                }
              end
            end
          end
        end
      end

      sig { params(integration: Integration).returns(String) }
      def oauth_authorization_url_for_integration(integration)
        query = { client_id: integration.key.to_s }.to_query
        "#{GitHub.url}/login/oauth/authorize?#{query}"
      end
    end
  end
end
