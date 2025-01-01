# typed: true
# frozen_string_literal: true

module Marketplace
  module Models
    module PlaygroundDependency
      extend T::Helpers
      include GitHub::Memoizer
      include Kernel
      include OcticonsHelper
      include FeatureFlagHelper

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

      STATIC_MODELS = T.let([], T::Array[GitHubModels::Types::Model])

      # Models in this list will display at the top of the page in this order. Models not in this list will display in
      # the normal alphabetical order
      MODEL_FAMILY_ORDER = %w(openai microsoft)

      abstract!

      sig { abstract.returns(T.nilable(User)) }
      def current_user; end

      # PlaygroundAccessResult returns whether or not a user can access the GitHub Models Playground
      # and backing Azure APIs, and if not, the reason why.
      class PlaygroundAccessResult < T::Struct
        const :accessible, T::Boolean
        const :reason, T.nilable(Symbol)

        sig { returns(T::Boolean) }
        def accessible?
          accessible
        end
      end

      # Returns accessible: true if the user is allowed to access the playground
      sig { params(user: T.nilable(User)).returns(PlaygroundAccessResult) }
      def check_playground_access(user: nil)
        user ||= current_user
        return PlaygroundAccessResult.new(accessible: false, reason: :no_user) unless user.present?
        user = T.must_because(user) { "user-specific attributes dictate access to Neutron" }

        if user.is_enterprise_managed?
          business = user.enterprise_managed_business
          return PlaygroundAccessResult.new(accessible: false, reason: :standalone_business) if business.copilot_licensing_enabled?
          return PlaygroundAccessResult.new(accessible: false, reason: :emu_disabled) unless business.models_access_enabled?
        end

        return PlaygroundAccessResult.new(accessible: false, reason: :blocked) if AzureModels::Block.blocked?(user)
        return PlaygroundAccessResult.new(accessible: false, reason: :spammy) if user.spammy?
        return PlaygroundAccessResult.new(accessible: false, reason: :suspended) if user.suspended?
        return PlaygroundAccessResult.new(accessible: false, reason: :trade_restrictions) if user.has_any_trade_restrictions?

        return PlaygroundAccessResult.new(accessible: false, reason: :copilot_blocked) if Copilot::User.new(user).administrative_blocked?

        if user.feature_enabled?(:project_neutron_emergency_restrict_access)
          if T.must(user.created_at) > 10.days.ago
            return PlaygroundAccessResult.new(accessible: false, reason: :temporary_restriction)
          end
        end

        PlaygroundAccessResult.new(accessible: true, reason: nil)
      end

      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def can_use_o1_models?(user)
        return false unless user.present?
        return true if user.feature_enabled?(:project_neutron_o1_models)

        copilot_public_user = Copilot::Public::User.new(T.must(user))

        return false if copilot_public_user.has_copilot_individual_free_access?

        copilot_public_user.has_copilot_access? && copilot_public_user.o1_enabled?
      end

      sig { returns(T::Array[GitHubModels::Types::Model]) }
      memoize def models
        item = AzureModels::CatalogItem.find_by(key: "all_models")
        return [] unless item

        (STATIC_MODELS + JSON.parse(item.value).map(&:deep_symbolize_keys)).sort_by do |m|
          family_index = MODEL_FAMILY_ORDER.index(m[:model_family].downcase) || MODEL_FAMILY_ORDER.length
          [family_index, m[:name]]
        end
      end

      # Returns a hash containing the model and schema that match the registry and model name
      sig do
        params(registry: String, model: String).returns({
          model: GitHubModels::Types::Model,
          schema: T.nilable(GitHubModels::Types::ModelSchema)
        })
      end
      def model_details(registry, model)
        static_model = STATIC_MODELS.find { |m| m[:registry] == registry && m[:name] == model }
        return {
          model: static_model,
          schema: nil
        } if static_model

        item = AzureModels::CatalogItem.find_by!(key: "#{registry}/#{model}")
        JSON.parse(item.value).deep_symbolize_keys
      end

      sig { params(model_name: String).returns(T.nilable(GitHubModels::Types::ModelDetails)) }
      def renderable_side_model(model_name)
        side_model_data = models.find { |model| model[:name] == model_name }
        return nil unless side_model_data.present?

        registry = side_model_data[:registry]
        name = side_model_data[:name]
        details = model_details(registry, name)
        return nil unless details.present?
        {
          catalogData: details[:model],
          modelInputSchema: details[:schema],
          gettingStarted: getting_started_table_of_contents(details[:model])
        }
      end

      # Generated a simplified table of contents for this model's getting
      # started content, with just the language and SDK names.
      # {
      #   [language]: {
      #     name: String,
      #     sdks: {
      #       [sdk_id]: {
      #         name: String,
      #         content: String,
      #         tocHeadings: Array,
      #         codeSamples: String,
      #       }
      #     }
      #   }
      # }
      sig { params(model: GitHubModels::Types::Model).returns(T::Hash[Symbol, T.untyped]) }
      def getting_started_table_of_contents(model)
        getting_started_content_entry(model).each_with_object({}) do |(language, language_entry), acc|
          acc[language] = {
            name: language_entry[:"name"],
            sdks: language_entry[:"sdks"].each_with_object({}) do |(sdk, sdk_entry), sdkacc|
              content = getting_started_content(model: model, language: language, sdk: sdk)
              sdkacc[sdk] = {
                name: sdk_entry[:"name"],
                content: content.output,
                tocHeadings: content[:toc_headers_hash],
                codeSamples: sdk_entry[:"code_sample"],
              }
            end
          }
        end
      end

      # returns { [model_id]: { [language]: { [sdk]: String } }
      sig { params(model: GitHubModels::Types::Model).returns(T::Hash[Symbol, T.untyped]) }
      def getting_started_content_entry(model)
        # Can't use the actual model[:id] here because it includes a version number,
        # whereas the toc.json file omits it.
        model_id = "azureml://registries/#{model[:registry]}/models/#{model[:original_name]}"
        content_entry = GitHubModels::Payloads::GettingStartedContent.fetch(model_id.to_sym)

        if content_entry.nil?
          if model[:static_model]
            content_entry = {}
          else
            raise ArgumentError
          end
        end

        content_entry
      end

      # Returns the content for the getting started guide, based on the
      # language and SDK specified in the params. If no language or SDK is
      # passed, it defaults to the first language and the first SDK in that
      # language. If the language or SDK is not found, it raises an
      # ArgumentError which causes the controller to 404.
      sig { params(model: GitHubModels::Types::Model, language: Symbol, sdk: Symbol).returns(GitHub::HTML::Result) }
      def getting_started_content(model:, language:, sdk:)
        language_entry = getting_started_content_entry(model)[language]

        raise ArgumentError if language_entry.nil?

        sdks = language_entry[:"sdks"]
        raise ArgumentError if sdks[sdk].nil?
        content = sdks[sdk][:"content"]

        url_model_name = model[:original_name]

        azure_link = if current_user
          "#{GitHub.azure_ai_github_url}?modelName=#{url_model_name}&ghid=#{T.must(current_user).analytics_tracking_id}"
        else
          "#{GitHub.azure_ai_github_url}?modelName=#{url_model_name}"
        end

        context = {
          anchor_icon: octicon("link"), # rubocop:disable Primer/PrimerOcticon
          azure_link: azure_link
        }

        GitHub::Goomba::ModelsMarkdownPipeline.call(content,
          context,
          # We can't cache because we're passing in a user-specific link. If we ever want to cache this, we'll need
          # to move the link generation to the client side.
          cache_settings: { use_cache: false },
        )
      end

      sig { params(url_identifier: String).returns(T.nilable(GitHubModels::Types::Preset)) }
      def renderable_preset(url_identifier)
        preset = AzureModels::Preset.find_by(url_identifier: url_identifier)

        return nil unless preset.present?
        return nil if preset.private? && !preset.belongs_to?(current_user)

        preset.json_payload
      end

      sig { returns(Integration) }
      memoize def neutron_app
        ::Apps::Privileged.integration(:neutron)
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

      sig { params(reason: T.nilable(Symbol)).returns(String) }
      def human_readable_reason(reason)
        case reason
        when :standalone_business, :emu_disabled
          "Models access is disabled for your business"
        when :blocked, :spammy, :suspended, :trade_restrictions, :copilot_blocked
          "Your account has been blocked for suspected abuse. Please contact Support"
        else
          "Failed to mint new auth token"
        end
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
