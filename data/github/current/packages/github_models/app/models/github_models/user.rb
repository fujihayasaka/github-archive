# typed: true
# frozen_string_literal: true

class GitHubModels::User
  include GitHub::Memoizer

  MODELS_GATEWAY_COMPLETIONS_PATH = "/inference/chat/completions"
  MODELS_GATEWAY_ORGS_COMPLETIONS_PATH = "/orgs/%{org_name}/inference/chat/completions"

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

  sig { returns T.nilable(::User) }
  attr_reader :user

  sig { params(user: T.nilable(::User)).void }
  def initialize(user:)
    @user = user
  end

  sig { params(org: T.nilable(Organization)).returns(String) }
  def playground_url(org: nil)
    if org&.feature_enabled?(:github_models_org_access_policies)
      org_completions_url(org.name)
    else
      GitHub.models_gateway_url + MODELS_GATEWAY_COMPLETIONS_PATH
    end
  end

  # Returns a list of models that are available to the user, sorted by the given sort order.
  sig { params(sort: T.nilable(Symbol)).returns(T::Array[GitHubModels::IModel]) }
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
    featured_models = GitHubModels.domain.models.find_many(featured_only: true)
    if featured_models.empty?
      # TODO Remove this once the 'featured' visibility is activated
      featured_models = models.select { |model| FALLBACK_FEATURED_MODELS.include?(model.name) }
    end

    publisher_sort(featured_models).map(&:to_featured_model)
  end

  # Public: Get the frontend representation of a model, enhanced with the set of capabilities that this user has
  # for the model.
  sig { params(model: GitHubModels::IModel).returns(GitHubModels::Types::Model) }
  def model_hash(model)
    apply_user_specific_capabilities(model.to_model)
  end

  sig { returns(T::Array[String]) }
  memoize def restricted_models
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
  memoize def is_staff?
    return false unless @user
    return true if @user.employee?
    return true if @user.businesses.exists?(slug: MICROSOFT_BUSINESS_SLUG)
    return true if @user.feature_enabled?(:project_neutron_staff_account)

    false
  end

  sig { returns(T::Array[String]) }
  memoize def access_flights
    # Azure uses flights to determine whether to apply expanded evals rate limits, so we
    # need to apply a special "evals" flight to the Models and Actions integrations
    if @user&.feature_enabled?(:github_models_higher_evals_rate_limits)
      return ["evals"] if @user.bot?
    end

    return [] unless @user&.user? # bots and organizations cannot have access flights

    ret = []

    # Only apply the evals flight if the user is authenticating via an integration (e.g. the Models UI app)
    ret << "evals" if @user.using_auth_via_integration? && @user.feature_enabled?(:github_models_higher_evals_rate_limits)

    ret << "o1-models" if can_use_o1_models?
    ret << "o3-models" if can_use_o3_models?
    ret << "rag" if @user.feature_enabled?(:project_neutron_rag)

    ret
  end

  sig { returns Integer }
  memoize def usage_tier
    if @user&.feature_enabled?(:github_models_bot_usage_tiers)
      return T.must(bot_usage_tier) if bot_usage_tier.present?
    end

    return USAGE_TIERS[:STAFF] if @user&.feature_enabled?(:project_neutron_higher_rate_limits)
    return USAGE_TIERS[:STAFF] if @user&.organizations.any? { |org| org.feature_enabled?(:project_neutron_higher_rate_limits) }
    return USAGE_TIERS[:STAFF] if @user&.businesses.any? { |business| business.feature_enabled?(:project_neutron_higher_rate_limits) }

    current_plan = copilot_user&.copilot_plan
    if current_plan == "enterprise"
      USAGE_TIERS[:ENTERPRISE]
    elsif current_plan == "business"
      USAGE_TIERS[:BUSINESS]
    else
      USAGE_TIERS[:FREE] # Free or Copilot Individual users get the same limits
    end
  end

  sig do
    params(
      actor: T.nilable(T.any(IntegrationInstallation, OauthApplication, OauthAccess, UserProgrammaticAccess))
    ).returns(T::Boolean)
  end
  def programmatic_actor_with_models_read_access?(actor)
    async_programmatic_actor_with_models_read_access?(actor).sync
  end

  sig do
    params(
      actor: T.nilable(T.any(IntegrationInstallation, OauthApplication, OauthAccess, UserProgrammaticAccess))
    ).returns(Promise[T::Boolean])
  end
  def async_programmatic_actor_with_models_read_access?(actor)
    return Promise.resolve(T.let(false, T::Boolean)) unless @user

    subject = @user.is_a?(Bot) ? @user.installation.target : @user

    authzd_actor = case actor
    when UserProgrammaticAccess
      UserProgrammaticAccessGrant.find_by(
        user_id: @user.id,
        user_programmatic_access_id: actor.id
      )
    when IntegrationInstallation
      OauthAuthorization.find_by(
        user_id: subject.id,
        application_id: actor.integration_id
      )
    when OauthAccess, OauthApplication
      return Promise.resolve(T.let(true, T::Boolean)) if actor.user_id == @user.id
    else
      nil
    end
    return Promise.resolve(T.let(false, T::Boolean)) if authzd_actor.nil?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :read_user_models,
      actor: authzd_actor,
      subject: subject,
    ).then { |decision| decision.allow? }
  end

  private

  sig { params(model_hash: GitHubModels::Types::Model).returns(GitHubModels::Types::Model) }
  def apply_user_specific_capabilities(model_hash)
    model_name = model_hash[:name]
    publisher = model_hash[:publisher]
    model_hash[:capabilities][:streaming] ||= streaming_feature_enabled_for_model?(model_name, publisher: publisher)
    model_hash
  end

  sig { params(model_name: String, publisher: String).returns(T::Boolean) }
  def streaming_feature_enabled_for_model?(model_name, publisher:)
    return false unless @user
    model_name.downcase == "o3" && publisher.downcase == "openai" &&
      @user.feature_enabled?(:github_models_o3_streaming)
  end

  # Returns the usage tier for a bot user, or nil if the user is not a bot
  sig { returns T.nilable(Integer) }
  memoize def bot_usage_tier
    return unless @user&.bot?

    org = T.cast(@user, ::Bot).installation.target
    return unless org&.organization?

    copilot_organization = Copilot::Organization.new(org)
    return USAGE_TIERS[:FREE] unless copilot_organization.copilot_enabled?

    if copilot_organization.copilot_plan == "enterprise"
      USAGE_TIERS[:ENTERPRISE]
    else
      USAGE_TIERS[:BUSINESS]
    end
  end

  sig { returns(T::Array[GitHubModels::IModel]) }
  memoize def unsorted_models
    visibilities = [:featured, :visible]
    visibilities << :staffshipped if @user&.employee?

    GitHubModels.domain.models.find_many(visibilities: visibilities)
  end

  # Sorts a list of models by publisher->alphabetical
  sig { params(items: T::Array[GitHubModels::IModel]).returns(T::Array[GitHubModels::IModel]) }
  def publisher_sort(items)
    items.sort_by do |m|
      publisher_index = PUBLISHER_ORDER.index(m.publisher&.downcase) || PUBLISHER_ORDER.length
      [publisher_index, m.name]
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

  sig { params(org_name: String).returns(String) }
  def org_completions_url(org_name)
    GitHub.models_gateway_url + MODELS_GATEWAY_ORGS_COMPLETIONS_PATH % { org_name: org_name }
  end
end
