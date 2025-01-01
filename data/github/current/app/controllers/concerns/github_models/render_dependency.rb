# typed: true
# frozen_string_literal: true

module GitHubModels::RenderDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer
  include GitHubModels::PlaygroundDependency

  abstract!

  requires_ancestor { ApplicationController }

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { returns GitHubModels::IModel }
  memoize def model
    model_for(params[:registry], params[:model])
  end

  sig { returns T.nilable(String) }
  def friendly_name
    model.friendly_name
  end

  def render_marketplace_model_show
    payload = GitHubModels::Payloads::Show.new(
      models_user: models_user,
      miniplayground_icebreaker: params[:p] || params[:prompt],
      model: models_user.model_hash(model),
      model_input_schema: model.to_schema,
      params: params,
      prompt_extraction_code_snippet: prompt_extraction_code_snippet,
      improved_prompt_model: get_improved_prompt_model,
      prompt_extraction_model: get_prompt_extraction_model,
    ).call

    render_react_app(
      app_payload_generator: -> { playground_app_payload },
      payload: payload,
      # We're not using SSR for the playground because of flickering issues when loading state from localStorage
      force_ssr: true,
      disable_ssr: false,
      title: "#{model.friendly_name} · GitHub Models",
      page_data: {
        full_height: true,
        full_height_scrollable: false,
        footer: false,
        title: "#{friendly_name} · GitHub Models",
        description: "Create AI-powered applications with #{friendly_name}",
        stafftools: stafftools_models_path,
        richweb: {
          title: "#{friendly_name} · GitHub Models · GitHub",
          url: request&.original_url,
          description: "Create AI-powered applications with #{friendly_name}",
          image: publisher_image,
        },
      },
    )
  end

  def render_playground_show
    payload = GitHubModels::Payloads::Show.new(
      models_user: models_user,
      miniplayground_icebreaker: params[:p] || params[:prompt],
      model: models_user.model_hash(model),
      model_input_schema: model.to_schema,
      params: params,
      prompt_extraction_code_snippet: prompt_extraction_code_snippet,
      improved_prompt_model: get_improved_prompt_model,
      prompt_extraction_model: get_prompt_extraction_model,
    ).call

    render_react_app(
      app_payload_generator: -> { playground_app_payload },
      payload: payload,
      # We're not using SSR for the playground because of flickering issues when loading state from localStorage
      force_ssr: false,
      disable_ssr: true,
      title: "#{model.friendly_name} · GitHub Models",
      page_data: {
        full_height: true,
        full_height_scrollable: false,
        footer: false,
        title: "#{friendly_name} · GitHub Models",
        description: "Create AI-powered applications with #{friendly_name}",
        stafftools: stafftools_models_path,
        richweb: {
          title: "#{friendly_name} · GitHub Models · GitHub",
          url: request&.original_url,
          description: "Create AI-powered applications with #{friendly_name}",
          image: publisher_image,
        },
      },
    )
  end

  def render_playground_index
    render_react_app(
      app_payload_generator: -> { playground_app_payload },
      payload: {
        playgroundUrl: models_user.playground_url,
        restrictedModels: models_user.restricted_models,
        featuredModels: models_user.featured_models,
      },
      disable_ssr: true,
      page_data: {
        full_height: true,
        full_height_scrollable: false,
        footer: false,
        title: "Models · GitHub Marketplace",
        description: "Create AI-powered applications with GitHub",
        richweb: {
          title: "Models · GitHub Marketplace · GitHub",
          url: request&.original_url,
          description: "Create AI-powered applications with GitHub",
          image: image_path("modules/marketplace/models/logo-models.jpg"),
        },
        stafftools: stafftools_models_path,
      },
    )
  end

  def playground_app_payload
    {
      current_user: { # keep in sync with `User` type in ui/packages/use-user/use-user.ts
        login: current_user&.display_login,
        name: current_user&.name,
        avatarUrl: current_user&.primary_avatar_url(80),
        path: user_path(current_user),
        analyticsTrackingId: current_user&.analytics_tracking_id,
      },
    }
  end

  sig { returns String }
  def publisher_image
    publisher_name = model.publisher&.downcase
    case publisher_name
    when "openai", "microsoft", "cohere", "meta", "core42", "xai"
      image_path("modules/marketplace/models/families/#{publisher_name}-hero.jpg")
    when "ai21 labs"
      image_path("modules/marketplace/models/families/ai21labs-hero.jpg")
    when "mistral ai"
      image_path("modules/marketplace/models/families/mistral-hero.jpg")
    else
      image_path("modules/marketplace/models/logo-models.jpg")
    end
  end

  # If there are content exclusion rules for the repo, don't allow prompt extraction. We should eventually
  # update this to actually check the specific paths, but since at this stage we're just validating whether people
  # would use this feature we'll come back to that later.
  def prompt_extraction_code_snippet
    return nil unless params[:l] && params[:n] && params[:c] && params[:path] && params[:lines]

    GitHub.dogstats.increment("github_models.prompt_extraction.attempt")
    GitHub.logger.info(
      "GitHub Models attempted to extract prompt",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.models.repository" => params[:l] + "/" + params[:n],
      "gh.models.extracted_lines" => params[:lines],
      "gh.models.extracted_path" => params[:path],
      "gh.models.extracted_commit" => params[:c],
    )

    left, right = params[:lines]&.split("-")&.map(&:to_i)
    return nil unless left && right

    repository = Repository.nwo("#{params[:l]}/#{params[:n]}")
    return nil unless repository

    # if the user can't access the repo, make sure we don't leak any information about whether there are
    # content exclusions/etc
    return nil unless repository.readable_by?(current_user)

    if repository.owner.is_a?(Organization) && ::Copilot::ContentExclusion.is_available?(repository.owner)
      paths = ::Copilot::ContentExclusion.rules_for_repo(repository).any?
      return nil if paths
    end

    blob = repository.blob(params[:c], params[:path])
    return nil unless blob

    GitHub.dogstats.increment("github_models.prompt_extraction.success")

    start_index = [left - 1, 0].max
    end_index = right - 1
    blob.lines[start_index..end_index].join("\n")
  end

  def check_user_can_view_model
    can_view = GitHubModels.domain.models.can_view?(user: current_user, registry: params[:registry],
      name: params[:model])
    render_404 unless can_view
  end

  def set_marketplace_context_region
    context_region_preset :marketplace_models
  end

  sig { returns T.nilable(GitHubModels::Types::Model) }
  def get_improved_prompt_model
    model = GitHubModels.domain.models.find(slug: "azure-openai/gpt-4o")
    return if model.nil?
    models_user.model_hash(model)
  end

  sig { returns T.nilable(GitHubModels::Types::Model) }
  def get_prompt_extraction_model
    model = GitHubModels.domain.models.find(slug: "azure-openai/gpt-4o-mini")
    return if model.nil?
    models_user.model_hash(model)
  end

  MODELS_CLIENT_SIDE_FEATURE_FLAGS = [
    :project_neutron_presets_allow_images,
    :github_models_search_filters,
    :project_neutron_rag,
    :github_models_billing_ui,
    :github_models_prompt_message_pair,
    :github_models_uploadable_attachments,
    :models_playground_disable_chat_history_param,
  ].freeze

  def add_models_client_side_feature_flags
    add_client_feature_flag(MODELS_CLIENT_SIDE_FEATURE_FLAGS)
    add_client_feature_flag([unstable_model_ff])
  end

  def unstable_model_ff
    return nil unless params[:model]
    "github_models_#{params[:model].downcase.gsub(/[-\s]/, "_")}_unstable".to_sym
  end
end
