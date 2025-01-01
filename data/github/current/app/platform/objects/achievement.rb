# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Achievement < Platform::Objects::Base
      include Platform::Helpers::AchievementUnlockingEvent

      implements Platform::Interfaces::UniformResourceLocatable

      description "An achievement unlocked by a user."

      mobile_only true

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

      implements_node templates: [[:ac, :user_id, :id]], as: "AC", ready_date: "1970-01-01" do |achievement|
        {
          prefix: :ac,
          user_id: achievement.user_id,
          id: achievement.id
        }
      end

      url_fields description: "The HTTP URL for this achievement" do |achievement|
        achievement.async_batch_safe_user.then do |user|
          UrlHelpers.user_achievement_url(
            host: GitHub.url,
            user_id: user,
            achievable_slug: achievement.achievable_slug,
          )
        end
      end

      field :user, Objects::User, null: true, method: :async_batch_safe_user,
        description: "The user who unlocked this achievement."

      field :achievable, Objects::Achievable, null: false,
        description: "Which kind of achievement this is."

      field :description_template, String, null: false,
        description: "Sentence explaining what the user did to unlock this achievement, including placeholders."

      field(
        :localized_description,
        String,
        null: false,
        description: "Sentence explaining what the user did to unlock this achievement.",
      ) do
        T.bind(self, GraphQL::Schema::Member::HasArguments)

        argument :locale, Enums::MobileLocale, required: true,
          description: "Locale to choose description language."
      end

      def localized_description(locale:)
        async_visible_unlocking_model_from(object).then do |unlocking_model|
          visible_models = unlocking_model ? [unlocking_model] : []

          ::Achievable::SubstitutedText.new(
            object.description_template(locale: locale),
            achievement: object,
            current_user: context[:viewer],
            visible_models: visible_models,
            locale: locale,
          ).async_render
        end
      end

      field :has_been_seen, Boolean, null: false, method: :seen?,
        description: "Has this user seen this achievement since it was unlocked?"

      field :is_fully_unlocked, Boolean, null: false,
        description: "True if this user has unlocked all available tiers of this Achievable, false otherwise."

      def is_fully_unlocked
        object.tier == object.achievable.highest_tier
      end

      field :is_hidden, Boolean, null: false, method: :hidden?,
        description: "True if the viewer has hidden this Achievement, false otherwise."

      field :unlocked_at, Scalars::DateTime, null: false,
        description: "Date and time when the first tier of this Achievement was unlocked."

      def unlocked_at
        # Read the unlock timestamp from the *lowest-tier* achievement associated with this user. Note that `object`
        # is the highest-tier.
        #
        # We fall back to reading the timestamp from `object` if something goes awry mostly so that we don't return
        # `nil`.
        object.async_user.then do |user|
          next object.unlocked_at unless user

          user.achievements_for(object.achievable).order(tier: :asc).first&.unlocked_at || object.unlocked_at
        end
      end

      field(
        :tier,
        Objects::AchievementTier,
        null: true,
        description: "Access a specific unlocked tier of this achievement.",
      ) do
        T.bind(self, GraphQL::Schema::Member::HasArguments)

        argument :number, Integer, required: true, description: "The one-indexed ordinal of the tier to fetch."
      end

      def tier(number:)
        object.async_user.then do |user|
          next nil unless user

          user.achievements_for(object.achievable).find_by(tier: number - 1)
        end
      end

      field :highest_tier, Objects::AchievementTier, null: false,
        description: "Highest-earned tier unlocked for this user."

      def highest_tier
        object.async_user.then do |user|
          next nil unless user

          user.highest_tier_achievement_for(object.achievable)
        end
      end

      field :tiers, [Objects::AchievementTier], null: false,
        description: "Collection of tiers unlocked by this user, ordered by ascending tier."

      def tiers
        object.async_user.then do |user|
          next nil unless user

          user.achievements_for(object.achievable).order(tier: :asc)
        end
      end
    end
  end
end
