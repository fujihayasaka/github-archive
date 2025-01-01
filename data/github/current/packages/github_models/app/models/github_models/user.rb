# typed: true
# frozen_string_literal: true

class GitHubModels::User
  include GitHub::Memoizer

  AZURE_AI_PLAYGROUND_COMPLETIONS_PATH = "/chat/completions"
  MODELS_GATEWAY_COMPLETIONS_PATH = "/inference/chat/completions"

  FALLBACK_FEATURED_MODELS = %w(
    gpt-4o
    DeepSeek-R1
    Llama-3-3-70B-Instruct
  ).freeze

  MICROSOFT_BUSINESS_SLUG = "microsoft"

  # Models in this list will display at the top of the page in this order. Models not in this list will display in
  # the normal alphabetical order
  PUBLISHER_ORDER = %w(openai microsoft).freeze

  USAGE_TIERS = {
    STAFF: 0,
    ENTERPRISE: 1,
    BUSINESS: 2,
    FREE: 3,
  }.freeze

  sig { params(user: T.nilable(::User)).void }
  def initialize(user:)
    @user = user
  end

  sig { returns String }
  memoize def playground_url
    if @user&.feature_enabled?(:github_models_gateway)
      GitHub.models_gateway_url + MODELS_GATEWAY_COMPLETIONS_PATH
    else
      GitHub.azure_ai_playground_url + AZURE_AI_PLAYGROUND_COMPLETIONS_PATH
    end
  end

  # Returns a list of models that are available to the user, sorted by the given sort order.
  sig { params(sort: T.nilable(Symbol)).returns(T::Array[GitHubModels::Types::Model]) }
  def models(sort: nil)
    case sort
    when :publisher
      publisher_sort(unsorted_models)
    else
      unsorted_models
    end
  end

  # Returns a list of featured models available to the user
  # Featured models are always sorted by publisher->alphabetical
  sig { returns(T::Array[GitHubModels::Types::FeaturedModel]) }
  memoize def featured_models
    items = GitHubModels::CatalogItem.featured.map(&:to_model)
    # TODO Remove this once the 'featured' visibility is activated
    items = models.select { |model| FALLBACK_FEATURED_MODELS.include?(model[:name]) } if items.empty?

    publisher_sort(items).map { |hash| GitHubModels::Types.featured_model_for(hash) }
  end

  sig { returns(T::Array[String]) }
  def restricted_models
    models = []

    if can_use_o1_models?
      models << "o1-mini"
      models << "o1-preview"
      models << "o1"
    end

    if can_use_o3_models?
      models << "o3-mini"
      models << "o3"
    end

    models
  end

  sig { returns(T::Boolean) }
  memoize def can_use_o1_models?
    copilot_public_user = self.copilot_public_user
    return false unless copilot_public_user
    return true if @user&.feature_enabled?(:project_neutron_o1_models)
    return false if copilot_public_user.has_copilot_individual_free_access?
    copilot_public_user.has_copilot_access? && copilot_public_user.o1_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def can_use_o3_models?
    copilot_public_user = self.copilot_public_user
    return false unless copilot_public_user
    return true if @user&.feature_enabled?(:project_neutron_o1_models)
    return false if copilot_public_user.has_copilot_individual_free_access?
    copilot_public_user.has_copilot_access? && copilot_public_user.o3_enabled?
  end

  # Governs whether you can see Models helpers in the code view experience (i.e. is Models enabled, are you
  # allowed to use Models, and is the blob you're looking at a likely candidate for a prompt and not blocked
  # from AI usage by Copilot content exclusions)
  def models_access_allowed_for_blob?(blob:, blob_url:, repository:)
    return false unless GitHub.models_enabled?

    return false unless @user&.feature_enabled?(:github_models_prompt_link)

    # Currently we're restricting Models PLG to user-owned repos.
    # If this is changed, we'll need to add a check here for any Copilot content exclusions
    return false unless repository.owner.user?

    # Heuristic to avoid showing GitHub Models helpers on files that are too large or don't include prompts
    return false unless blob.data.size < 10.megabytes
    return false unless GitHubModels::PromptDetector.text_probably_contains_prompt?(blob_url + blob.data)

    return false unless GitHubModels::PlaygroundAccessResult.for(@user).accessible?

    GitHub.dogstats.increment("github_models.prompt_gutter_menu_available")

    true
  end

  sig { returns T::Boolean }
  def is_staff?
    return false unless @user
    return true if @user.employee?
    return true if @user.businesses.exists?(slug: MICROSOFT_BUSINESS_SLUG)
    return true if @user.feature_enabled?(:project_neutron_staff_account)

    false
  end

  sig { returns(T::Array[String]) }
  def access_flights
    return [] unless @user&.user? # bots and organizations cannot have flights

    ret = []
    ret << "o1-models" if can_use_o1_models?
    ret << "o3-models" if can_use_o3_models?
    ret << "rag" if @user.feature_enabled?(:project_neutron_rag)

    ret
  end

  sig { returns Integer }
  def usage_tier
    return USAGE_TIERS[:STAFF] if @user&.feature_enabled?(:project_neutron_higher_rate_limits)

    current_plan = copilot_user&.copilot_plan
    if current_plan == "enterprise"
      USAGE_TIERS[:ENTERPRISE]
    elsif current_plan == "business"
      USAGE_TIERS[:BUSINESS]
    else
      USAGE_TIERS[:FREE] # Free or Copilot Individual users get the same limits
    end
  end

  private

  sig { returns(T::Array[GitHubModels::Types::Model]) }
  memoize def unsorted_models
    visibilities = [:featured, :visible]
    visibilities << :staffshipped if @user&.employee?

    GitHubModels::CatalogItem.where(visibility: visibilities).map(&:to_model)
  end

  # Sorts a list of models by publisher->alphabetical
  sig { params(items: T::Array[GitHubModels::Types::Model]).returns(T::Array[GitHubModels::Types::Model]) }
  def publisher_sort(items)
    items.sort_by do |m|
      publisher_index = PUBLISHER_ORDER.index(m[:publisher].downcase) || PUBLISHER_ORDER.length
      [publisher_index, m[:name]]
    end
  end

  sig { returns T.nilable(Copilot::Public::User) }
  memoize def copilot_public_user
    return unless @user
    Copilot::Public::User.new(@user)
  end

  sig { returns T.nilable(Copilot::User) }
  memoize def copilot_user
    return unless @user
    Copilot::User.new(@user)
  end
end
