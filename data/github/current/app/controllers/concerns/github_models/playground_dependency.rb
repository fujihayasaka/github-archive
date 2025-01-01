# typed: true
# frozen_string_literal: true

module GitHubModels::PlaygroundDependency
  extend T::Helpers
  include GitHub::Memoizer
  include Kernel
  include OcticonsHelper
  include FeatureFlagHelper

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

  sig { returns(GitHubModels::User) }
  memoize def models_user
    GitHubModels::User.new(user: current_user)
  end

  sig { params(registry: String, name: String).returns(GitHubModels::IModel) }
  def model_for(registry, name)
    @models_by_slug ||= {}
    slug = GitHubModels.domain.models.slug_for(registry: registry, name: name)
    @models_by_slug[slug] ||= GitHubModels.domain.models.find!(slug: slug)
  end

  sig { params(model_name: String, repository: T.nilable(GitHubModels::Repository)).returns(T.nilable(GitHubModels::Types::ModelDetails)) }
  def renderable_side_model(model_name, repository: nil)
    # Todo: when dropping all_models entry, the def models functions will get all rows from db.
    # so to get all rows and filter here would be very inefficient.
    # Change this to read the correct row from db directly intead. However, UI need to pass registry/model since
    # that is the unique key. So saving for future PR to resolve.
    side_model_data = models_user.models(sort: :publisher).find { |model| model.name == model_name }
    return nil unless side_model_data

    registry = side_model_data.registry
    name = side_model_data.name
    return unless registry.present? && name.present?

    if repository.present?
      # check if the model is restricted for this repository
      available_models = repository.models(user: models_user)
      return nil unless available_models.find { |m| m[:name] == model_name && m[:registry] == registry }
    end

    model = model_for(registry, name)
    catalog_data = models_user.model_hash(model)
    schema = model.to_schema
    {
      catalogData: catalog_data,
      modelInputSchema: schema,
      gettingStarted: getting_started_table_of_contents(catalog_data, schema)
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
  sig { params(model: GitHubModels::Types::Model, schema: T.nilable(GitHubModels::Types::ModelSchema)).returns(T::Hash[Symbol, T.untyped]) }
  def getting_started_table_of_contents(model, schema)
    getting_started_content_entry(model, schema).each_with_object({}) do |(language, language_entry), acc|
      acc[language] = {
        name: language_entry[:"name"],
        sdks: language_entry[:"sdks"].each_with_object({}) do |(sdk, sdk_entry), sdkacc|
          content = getting_started_content(model: model, language_entry: language_entry, sdk: sdk)
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
  sig { params(model: GitHubModels::Types::Model, schema: T.nilable(GitHubModels::Types::ModelSchema)).returns(T::Hash[Symbol, T.untyped]) }
  def getting_started_content_entry(model, schema)
    # Can't use the actual model[:id] here because it includes a version number,
    # whereas the toc.json file omits it.
    model_id = "azureml://registries/#{model[:registry]}/models/#{model[:original_name]}"
    content_entry = GitHubModels::Payloads::GettingStartedContent.fetch(model_id.to_sym)

    # Currently all models in our Catalog has a content_entry in GitHubModels::Payloads::GettingStartedContent.
    # However, to enable faster shipping of more models we want to sync models even without premade content.
    # In those cases we will use the rendered content below as fallback (therefore the OR content_entry.nil)
    if current_user&.feature_enabled?(:github_models_dynamic_getting_started_content) || content_entry.nil?
      content_entry = GitHubModels::DocumentationController.new.render_getting_started_content(model, schema).deep_symbolize_keys
    end

    content_entry
  end

  # Returns the content for the getting started guide, based on the
  # language and SDK specified in the params. If no language or SDK is
  # passed, it defaults to the first language and the first SDK in that
  # language. If the language or SDK is not found, it raises an
  # ArgumentError which causes the controller to 404.
  sig { params(model: GitHubModels::Types::Model, language_entry: T::Hash[Symbol, T.untyped], sdk: Symbol).returns(GitHub::HTML::Result) }
  def getting_started_content(model:, language_entry:, sdk:)
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
      azure_link: azure_link,
      add_tabindex_to_headings: true,
    }

    GitHub::Goomba::ModelsMarkdownPipeline.call(content,
      context,
      # We can't cache because we're passing in a user-specific link. If we ever want to cache this, we'll need
      # to move the link generation to the client side.
      cache_settings: { use_cache: false },
    )
  end

  sig { params(slug: String).returns(T.nilable(GitHubModels::Types::Preset)) }
  def renderable_preset(slug)
    preset = GitHubModels.domain.presets.find(slug: slug)

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
    key = T.must_because(GitHub.models_simple_box_key) { "must have an encryption key set" }

    RbNaCl::SimpleBox.from_secret_key(key.b)
  end
end
