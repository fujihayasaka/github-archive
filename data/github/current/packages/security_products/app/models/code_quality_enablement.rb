# typed: strict
# frozen_string_literal: true

class CodeQualityEnablement < SecurityProduct::Service
  include SecurityProduct::Service::ActionsChecks

  # Validates that the prerequisites for enabling Code Quality are met
  sig { params(repository: Repository, current_user: T.nilable(User), options: T.nilable(T::Hash[Symbol, T.untyped])).returns(T.nilable(Symbol)) }
  def self.validate_prerequisites(repository, current_user, options)
    # 1 - Repository must not be archived
    if repository.archived?
      return :repo_archived
    end

    # 2 - Repository must belong to an organization (because we're only available on Team or GHEC plans)
    if !repository.owner&.organization?
      return :repo_not_in_organization
    end

    # 3 - Instance Actions must be enabled
    if !GitHub.actions_enabled?
      if current_user&.site_admin? && !GitHub.cluster_regular_enabled?
        return :instance_actions_disabled_admin
      else
        return :instance_actions_disabled
      end
    end

    # 4 - Repository Actions must be enabled
    if repository.actions_disabled?
      if repository.actions_disabled_by_owner?
        return :repo_actions_disabled_by_owner
      else
        return :repo_actions_disabled
      end
    end

    # 5 - Check enterprise policy
    if current_user.present?
      reason = self.policy_check(repository:, current_user:).error
      return reason if reason.present? && reason.is_a?(Symbol)
    end

    # 6 - Check runner requirements
    CodeScanning::Status.validate_default_setup_runners(repository, options: options)
  end

  sig { params(repository: Repository, current_user: User).returns(SecurityProduct::Result) }
  def self.policy_check(repository:, current_user:)
    return SecurityProduct::Result.new(false, :code_quality_not_allowed_by_policy) unless CodeQualityAccessPolicyConfig.new(repository).policy_allows_code_quality_enablement?

    return SecurityProduct::Result.new(false, :code_quality_restricted_by_enablement_policy) if blocked_by_enablement_policy?(repository: repository, actor: current_user)

    SecurityProduct::Result.new(true)
  end

  sig { params(repository: Repository, actor: User).returns(T::Boolean) }
  def self.blocked_by_enablement_policy?(repository:, actor:)
    business = repository.owner&.business
    return false unless business # do not block for non-business repos

    allow_repo_admins = business.repo_admins_can_modify_code_quality_enablement?
    return false if allow_repo_admins

    !self.async_allow?(repository, actor, :manage_repo_code_quality_settings, context: { allow_repo_admins: false }).sync
  end

  sig { params(repository: Repository, actor: User, action: Symbol, context: T.nilable(T::Hash[Symbol, T.untyped])).returns(Promise[T::Boolean]) }
  def self.async_allow?(repository, actor, action, context: nil)
    return Promise.resolve(T.let(false, T::Boolean)) unless actor.user? # Reject bots
    return Promise.resolve(T.let(false, T::Boolean)) if repository.advisory_workspace? # There's no security pages in advisory workspace/temporary fork repos

    GitHub.logger.with_named_tags(**user_tags(actor), **repository_tags(repository), "gh.authzd.attributes.action": action) do
      GitHub.logger.info("Check authorization", "code.namespace": name, "code.function": __method__)
      Platform::Loaders::Permissions::BatchAuthorize.load(
        action:,
        actor:,
        subject: repository,
        context:,
      ).then(&:allow?)
    end
  end
  private_class_method :async_allow?

  sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
  def self.user_tags(user)
    {
      "enduser.id": user.display_login,
      "gh.enduser.id": user.id,
      "gh.enduser.login": user.display_login,
    }
  end
  private_class_method :user_tags

  sig { params(repository: Repository).returns(T::Hash[Symbol, T.untyped]) }
  def self.repository_tags(repository)
    {
      "gh.repo.id": repository.id,
      "gh.repo.name": repository.name,
      "gh.repo.name_with_owner": repository.name_with_display_owner,
    }
  end
  private_class_method :repository_tags

  # This is a quicker prerequisite check we do before every run.
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.required_run_conditions_met?(repository)
    !!(repository.actions_enabled? && repository.owner&.organization?)
  end

  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def can_enable?(actor:, options:)
    return SecurityProduct::Result.new(false, :not_part_of_preview) unless CodeQuality.available?(repository)
    error = self.class.validate_prerequisites(repository, actor, options:)
    return SecurityProduct::Result.new(false, error) if error.present?
    SecurityProduct::Result.new(true)
  end

  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def can_disable?(actor:, options:)
    return SecurityProduct::Result.new(false, :code_quality_restricted_by_enablement_policy) if self.class.blocked_by_enablement_policy?(repository: repository, actor: actor)

    SecurityProduct::Result.new(true)
  end

  sig { returns(CodeScanning::ManagedAnalysesLanguageSupport) }
  def language_support
    @language_support ||= T.let(managed_analyses_helper.language_support, T.nilable(CodeScanning::ManagedAnalysesLanguageSupport))
  end

  sig { returns(CodeScanning::ManagedAnalysesConfig) }
  def recommended_configuration
    config = recommended_configuration_without_runner_labels
    config.runner_label = default_runner_label

    config
  end

  sig { returns(T.nilable(String)) }
  def default_runner_label
    if GitHub.enterprise? ||
      SecurityProductsEnablement::Actions::RunnerChecker.new(repository).labelled_runners_available?(
        desired_labels: [CodeScanning::AutoCodeql::DEFAULT_RUNNER_LABEL],
        calling_context_only_for_metrics: :code_quality_default)

      CodeScanning::AutoCodeql::DEFAULT_RUNNER_LABEL
    end
  end

  sig { returns(T::Array[String]) }
  def supported_languages
    @supported_languages ||= T.let(language_support.supported_languages, T.nilable(T::Array[String]))
  end

  sig { params(languages_to_add: T::Array[String], languages_to_delete: T::Array[String]).void }
  def update_languages(languages_to_add:, languages_to_delete:)
    managed_analyses_helper.update_languages(languages_to_add: languages_to_add, languages_to_delete: languages_to_delete)
  end

  # The recommended configuration but without setting a recommended runner label.
  # This is to avoid the expensive check to determine whether runners with the `code-scanning`
  # label are available.
  # Use `recommended_configuration` if you need runner label information.
  sig { returns(CodeScanning::ManagedAnalysesConfig) }
  def recommended_configuration_without_runner_labels
    CodeScanning::ManagedAnalysesConfig.new(
      state: "not-configured",
      languages: supported_languages,
      query_suite: "default",
      threat_model: "remote",
      updated_at: nil,
      schedule: nil,
      initial_languages: [],
      creation_trigger: nil,
      runner_label: nil,
      code_quality_enabled: false,
      )
  end

  sig { params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def enable_or_update(actor:, options:)
    config = recommended_configuration_without_runner_labels.with_options(options)

    case options[:runner_type].to_s
    when "standard" then
      update_runner_label = true
      config.runner_label = nil
    when "labeled" then
      if options[:runner_label].present? && actions_runner_checker&.labelled_runners_available?(desired_labels: [options[:runner_label]], calling_context_only_for_metrics: :auto_codeql_update)
        update_runner_label = true
        config.runner_label = options[:runner_label]
      else
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), :runner_not_available)
      end
    else
      update_runner_label = false
    end

    resp = T.let(nil, T.nilable(T.any(Twirp::ClientResp[Turboscan::Proto::EnableResponse], Twirp::ClientResp[Turboscan::Proto::UpdateResponse])))
    update = T.let(false, T::Boolean)
    case options[:action]
    when :update
      update = true
      resp = managed_analyses_helper.update_managed_analysis(actor:, config:, update_runner_label:)
    when :enable
      update = false
      config.runner_label = default_runner_label unless update_runner_label
      resp = managed_analyses_helper.enable_managed_analysis(actor:, config:)
    when nil
      if disabled?
        update = false
        config.runner_label = default_runner_label unless update_runner_label
        resp = managed_analyses_helper.enable_managed_analysis(actor:, config:)
      else
        update = true
        resp = managed_analyses_helper.update_managed_analysis(actor:, config:, update_runner_label:)
      end
    else
      raise ArgumentError, "Invalid action #{options[:action]}"
    end

    if resp.nil? || resp.data.nil? || resp.error.present?
      if update
        # TODO Move error message definitions out of AutoCodeql class (into helper?)
        error_message = CodeScanning::AutoCodeql::ERROR_MESSAGES[:turboscan_update_failed]

        if resp&.error&.code == :already_exists
          error_message = "Configuration update already in progress"
          options[:already_exists] = true
        end

        error = CodeScanning::AutoCodeqlError.new(error_message, repo_id: @repository.id, twirp_error: resp&.error)
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), error)
      else
        error = CodeScanning::AutoCodeqlError.new(CodeScanning::AutoCodeql::ERROR_MESSAGES[:turboscan_onboard_failed], repo_id: @repository.id, twirp_error: resp&.error)
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, options), error)
      end
    end

    options[:workflow_run_id] = resp.data.workflow_run_id
    options[:noop] = true if resp.data.noop

    SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
  end

  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def on_enable(actor:, options:)
    opts = {
      action: options[:action],
      code_quality_enabled: \
        if options[:action] == :update
          Turboscan::Proto::UpdateRequest::CodeQualityEnablement::CODE_QUALITY_UNCHANGED
        else
          Turboscan::Proto::UpdateRequest::CodeQualityEnablement::CODE_QUALITY_ENABLED
        end
    }

    if options[:action] == :update
      # Always pass in languages, even if empty array since this is a valid turboscan usecase
      opts[:languages] = options[:languages]
      opts[:runner_label] = options[:runner_label] if options[:runner_label].present?
      opts[:runner_type] = options[:runner_type] if options[:runner_type].present?
    end

    result = enable_or_update(actor:, options: opts)

    if result.error?
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, result.error)
    else
      publish_instrumentation(enabled: true) unless options[:action] == :update
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end
  end

  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def on_disable(actor:, options:)
    result = managed_analyses_helper.disable_managed_analyses(actor:)
    if result&.error.present?
      error = CodeScanning::AutoCodeqlError.new(CodeScanning::AutoCodeql::ERROR_MESSAGES[:turboscan_disable_failed], repo_id: @repository.id, twirp_error: result&.error)
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, error)
    else
      publish_instrumentation(enabled: false)
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    return false if repository.deleted?
    return false unless CodeQuality.available?(repository)
    managed_analyses_helper.enabled?
  rescue CodeScanning::AutoCodeqlError => error
    if GitHub::AppEnvironment.development?
      false
    else
      raise
    end
  end

  sig { override.returns(Symbol) }
  def to_sym
    :code_quality
  end

  sig { override.returns(String) }
  def self.name
    "Code Quality"
  end

  sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
  def self.error_to_message(symbol)
    case symbol
    when :not_part_of_preview
      "This organization is not part of the code quality preview."
    when :auto_codeql_not_enabled
      "Code Scanning default setup is not enabled on this repository."
    when :runner_not_available, :no_runner_assigned
      "Code Quality can only be enabled if a runner with the specified label is assigned to this repository."
    when :repo_archived
      "Code Quality cannot be enabled on archived repositories."
    when :instance_actions_disabled_admin
      "Code Quality can only be enabled if Actions is enabled. GitHub Actions is not enabled on this instance, please configure Actions."
    when :instance_actions_disabled
      "Code Quality can only be enabled if Actions is enabled. GitHub Actions is not enabled on this instance, please ask your instance administrator to configure Actions."
    when :repo_actions_disabled_by_owner
      "Code Quality can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository by an enterprise or organization policy. Please ask your organization administrator to enable Actions."
    when :repo_actions_disabled
      "Code Quality can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it."
    when :actions_policy_disabled
      "GitHub Actions policy is limiting the use of some required actions. To use Code Quality, allow actions from `actions/*` and `github/codeql-action/*`."
    when :no_macos_runners_assigned
      "Code Quality for Swift can only be enabled if runners with both the specified and macOS labels are assigned to this repository."
    when :repo_not_in_organization
      "Code Quality can only be enabled on repositories that belong to an organization."
    when :advanced_security_disabled
      "Code Quality can only be enabled on repositories where Advanced Security is enabled."
    when :code_security_disabled
      "Code Quality can only be enabled on repositories where Code Security is enabled."
    when :code_quality_restricted_by_enablement_policy, :code_quality_not_allowed_by_policy, :code_security_not_allowed_by_policy, :code_security_restricted_by_enablement_policy
      "An organization or enterprise policy prevents changing the Code Quality setting."
    else
      super
    end
  end

  sig { returns(T.nilable(Time)) }
  def next_scheduled_run_at
    managed_analyses_helper.next_scheduled_run_at
  end

  sig { returns(CodeScanning::ManagedAnalysesConfig) }
  def configuration
    @configuration ||= T.let(managed_analyses_helper.configuration, T.nilable(CodeScanning::ManagedAnalysesConfig))
  end

  sig { returns(T::Boolean) }
  def disabled?
    managed_analyses_helper.disabled?
  end

  sig { returns(T::Boolean) }
  def enabling?
    managed_analyses_helper.enabling?
  end

  sig { returns(T::Boolean) }
  def updating?
    managed_analyses_helper.updating?
  end

  sig { returns(T::Boolean) }
  def has_failed_update?
    managed_analyses_helper.has_failed_update?
  end

  sig { returns(T::Boolean) }
  def waiting?
    return false if repository.deleted?
    managed_analyses_helper.waiting?
  end

  sig { returns(T::Boolean) }
  def is_private_preview_config?
    managed_analyses_helper.is_private_preview_config?
  end

  sig { returns(T.nilable(Integer)) }
  def get_actions_workflow_run_id
    managed_analyses_helper.get_workflow_run_id
  end

  private

  sig { returns(CodeScanning::AutoCodeql) }
  def auto_codeql
    @auto_codeql ||= T.let(CodeScanning::AutoCodeql.new(repository), T.nilable(CodeScanning::AutoCodeql))
  end

  sig { returns(CodeScanning::ManagedAnalysesEnablement) }
  def managed_analyses_helper
    disabled_by_prerequisites = !self.class.required_run_conditions_met?(@repository)
    @enablement_status ||= T.let(CodeScanning::ManagedAnalysesEnablement.new(repository, :CODE_QUALITY, disabled_by_prerequisites), T.nilable(CodeScanning::ManagedAnalysesEnablement))
  end

  sig { params(enabled: T::Boolean).void }
  def publish_instrumentation(enabled:)
    GlobalInstrumenter.instrument(
      "code_quality.toggled",
      repository_id: repository.id,
      feature_enabled: enabled,
    )

    CodeQuality::RepositoryUpdatePublisher.publish_repository(
      repo: repository,
      code_quality_enabled: enabled,
    )
  end
end
