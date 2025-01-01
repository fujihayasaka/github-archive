# typed: true
# frozen_string_literal: true

module Marketplace
  module Models
    module PlaygroundDependency
      extend T::Sig
      extend T::Helpers
      include GitHub::Memoizer

      FEATURED_MODEL_NAMES = %w(
        gpt-4o-mini
        Meta-Llama-3-1-405B-Instruct
        Mistral-large-2407
      ).freeze

      # Cache keys and TTLs
      MODELS_LIST_CACHE_KEY = "azure_ai_studio:v2:models_list"
      MODELS_LIST_CACHE_TTL = 1.hour.to_i
      RENDERABLE_MODEL_CACHE_TTL = 1.hour.to_i

      # Cache lookup metrics
      MODELS_LIST_CACHE_METRIC = "github_models.models_list.cache_result"
      RENDERABLE_MODEL_CACHE_METRIC = "github_models.renderable_model.cache_result"

      abstract!

      sig { abstract.returns(T.nilable(User)) }
      def current_user; end

      # PlaygroundAccessResult returns whether or not a user can access the GitHub Models Playground
      # and backing Azure APIs, and if not, the reason why.
      class PlaygroundAccessResult < T::Struct
        extend T::Sig
        const :accessible, T::Boolean
        const :reason, T.nilable(Symbol)

        def accessible?
          accessible
        end
      end

      # Returns true if the user is allowed to access the Neutron playground. This
      # method includes checks for spammy or suspended users, as well as the
      # project_neutron_playground feature flag.
      sig { returns(PlaygroundAccessResult) }
      def check_playground_access
        user = current_user
        return PlaygroundAccessResult.new(accessible: false, reason: :no_user) unless user.present?
        user = T.must_because(user) { "user-specific attributes dictate access to Neutron" }

        feature_flag_enabled = user.feature_enabled?(:project_neutron_playground)
        return PlaygroundAccessResult.new(accessible: false, reason: :feature_flag_disabled) unless feature_flag_enabled
        return PlaygroundAccessResult.new(accessible: false, reason: :spammy) if user.spammy?
        return PlaygroundAccessResult.new(accessible: false, reason: :suspended) if user.suspended?
        return PlaygroundAccessResult.new(accessible: false, reason: :trade_restrictions) if user.has_any_trade_restrictions?

        PlaygroundAccessResult.new(accessible: true, reason: nil)
      end

      sig { returns(T::Array[Marketplace::Types::AzureModels::Model]) }
      memoize def models
        item = AzureModels::CatalogItem.find_by(key: "all_models")
        return [] unless item

        JSON.parse(item.value).map(&:deep_symbolize_keys)
      end

      def model_details(registry, model)
        item = AzureModels::CatalogItem.find_by!(key: "#{registry}/#{model}")
        JSON.parse(item.value).deep_symbolize_keys
      end

      sig { returns(Integration) }
      memoize def neutron_app
        ::Apps::Internal.integration(:neutron)
      end

      sig { params(user_session: UserSession).returns({ expiration: Time, token: String }) }
      def generate_oauth_token(user_session)
        user = T.must_because(user_session.user) { "we expect user_session to always have a user" }

        new_access = neutron_app.grant(user, { user_session: user_session })

        # NOTE: despite the name `extended_expiry`, we are actually expiring the tokens much sooner than the default.
        #       the flag is used internally to read from the internal app's `oauth_access_expiry` property.
        token, _ = new_access.redeem(extended_expiry: true)

        encrypted = simple_box.encrypt(token)

        # The encrypted token gets passed around to the browser and ultimately into an HTTP header in requests to CAPI,
        # so it needs to be URL encoded/decoded.
        encoded = Base64.urlsafe_encode64(encrypted)

        {
          expiration: new_access.expires_at,
          token: encoded,
        }
      end

      private

      sig { returns(RbNaCl::SimpleBox) }
      memoize def simple_box
        key = T.must_because(GitHub.neutron_simple_box_key) { "must have an encryption key set" }

        RbNaCl::SimpleBox.from_secret_key(key.b)
      end
    end
  end
end
