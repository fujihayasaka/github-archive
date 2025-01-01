# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AchievementTier < Platform::Objects::Base
      include Platform::Helpers::AchievementUnlockingEvent

      model_name "Achievement"
      description "Specific unlocked tier of an Achievement."

      required_capabilities [:mobile_only_schema_mask]

      scopeless_tokens_as_minimum

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        !object.hidden? || object.user_id == permission.viewer&.id
      end

      implements_node templates: [[:at, :user_id, :id]], as: "AT", ready_date: nil do |achievement|
        {
          prefix: :at,
          user_id: achievement.user_id,
          id: achievement.id
        }
      end

      field :user, Objects::User, null: true, method: :async_batch_safe_user,
        description: "User who unlocked this Achievement tier."

      field :achievement, Objects::Achievement, null: false, method: :highest_tier_achievement,
        description: "Achievement this tier belongs to."

      field :unlocked_at, Scalars::DateTime, null: false,
        description: "Date and time when this Achievement tier was unlocked."

      field :unlocking_model, Unions::UnlockingModel, null: true,
        description: "Model describing the activity that triggered this tier to be unlocked." \
          "May be null if the model is deleted or otherwise inaccessible."

      def unlocking_model
        async_visible_unlocking_model_from(object)
      end

      field :unlocking_explanation_template, String, null: false,
        description: "Text explaining the activity that triggered this tier's unlocking, including placeholders."

      field(
        :localized_unlocking_explanation,
        String,
        null: false,
        description: "Text explaining the activity that triggered this tier's unlocking.",
      ) do
        T.bind(self, GraphQL::Schema::Member::HasArguments)

        argument :locale, Enums::MobileLocale, required: true,
          description: "Locale to choose unlocking explanation language."
      end

      def localized_unlocking_explanation(locale:)
        async_visible_unlocking_model_from(object).then do |unlocking_model|
          visible_models = unlocking_model ? [unlocking_model] : []

          ::Achievable::SubstitutedText.new(
            object.unlocking_explanation_template(locale: locale),
            achievement: object,
            current_user: context[:viewer],
            visible_models: visible_models,
            locale: locale,
          ).async_render
        end
      end

      field :tier_number, Integer, null: false,
        description: "Tier ordinal, one-indexed."

      def tier_number
        object.tier + 1
      end

      field :tier_name, Enums::AchievementTierName, null: false, method: :tier,
        description: "Metallic-color name corresponding to this tier."

      field :badge_image_url, Scalars::URI, null: false,
        description: "URL for the image asset corresponding to this tier's graphic."

      def badge_image_url
        if object.achievable.has_rounded_badge_variant?
          # None of the achievables with rounded badge variants have multiple tiers or skin tone variants, so we can
          # keep this really simple.
          return object.achievable.rounded_badge_asset_url
        end

        object.async_user.then do |user|
          skin_tone_block = if user
            -> { user.profile_settings.preferred_emoji_skin_tone }
          else
            -> { 0 }
          end

          object.achievable.badge_asset_url(tier: object.tier, skin_tone_block: skin_tone_block)
        end
      end

      field :gradient_image_url, Scalars::URI, null: false,
        description: "URL for the background gradient image asset corresponding to this achievement and tier."

      def gradient_image_url
        object.achievable.gradient_asset_url
      end

      field :background_color, String, null: false,
        description: "Hex color code for a uniform background suitable for the display for this achievement and tier."

      def background_color
        object.achievable.background_color
      end

      field :social_image_url, Scalars::URI, null: false,
        description: "URL for the image asset used in our Twitter hovercards."

      def social_image_url
        object.async_user.then do |user|
          skin_tone_block = if user
            -> { user.profile_settings.preferred_emoji_skin_tone }
          else
            -> { 0 }
          end

          object.achievable.social_card_asset_url(
            tier: object.tier,
            skin_tone_block: skin_tone_block,
          )
        end
      end

      field :high_resolution_badge_image_url, Scalars::URI, null: false,
          description: "URL for a high-resolution badge image."

      def high_resolution_badge_image_url
        object.achievable.high_resolution_asset_url
      end
    end
  end
end
