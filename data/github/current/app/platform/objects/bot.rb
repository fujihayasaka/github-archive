# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Bot < Platform::Objects::Base
      description "A special type of user which takes actions on behalf of GitHub Apps."

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
    end
  end
end
