# typed: true
# frozen_string_literal: true

class SecurityAnalysisSettingsUpdateJob < TimedJob
  include SecretScanning::Features::FeatureFlagHelper

  class ToggleServicesError < StandardError; end

  Owner = T.type_alias { T.any(User, Organization) }

  EMIT_BACKFILL_GROUP_REQUEST_DEFAULT = true
  LONG_RUNNING_SEQUENCE_HOURS = 1

  queue_as :security_analysis_settings

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on ToggleServicesError, attempts: 3, wait: :polynomially_longer

  locked_by timeout: ApplicationJob::DEFAULT_TIMEOUT, key: ->(job) do
    ## validate_args will decrement the business enablement job counter for this job
    ## if it is a child job of business enablement and argument validation fails
    owner, update_type = SecurityAnalysisSettingsUpdateJob.validate_args(job)

    "#{self.prefix}-#{owner.class.name.underscore}-#{owner.id}-#{update_type}"
  end

  # Upsert a SecurityProductsEnablement::JobStatus in before_enqueue and before_perform to ensure a
  # SecurityProductsEnablement::JobStatus is created ASAP for perform_later or perform_now.
  before_enqueue do |job|
    ## validate_args will decrement the business enablement job counter for this job
    ## if it is a child job of business enablement and argument validation fails
    owner, update_type = SecurityAnalysisSettingsUpdateJob.validate_args(job)

    job.upsert_job_status(owner, update_type)
  end

  around_perform do |job, blk|
    ## validate_args will decrement the business enablement job counter for this job
    ## if it is a child job of business enablement and argument validation fails
    owner, update_type = SecurityAnalysisSettingsUpdateJob.validate_args(job)

    job.upsert_job_status(owner, update_type).track { blk.call }
  end

  sig { params(job: T.untyped).returns([T.untyped, T.untyped]) }
  def self.validate_args(job)
    owner, update_type = (job.arguments[0] || {}).values_at(:owner, :update_type)
    if owner.nil? || update_type.nil?
      is_business_enablement, parent_initial_sequence_id = (job.arguments[0] || {}).values_at(:business_enable, :parent_initial_sequence_id)
      ## If this is a child job of business enablement, the decrement the job counter.
      SecurityAnalysisSettingsUpdateJob.decrement_business_enablement_counter(parent_initial_sequence_id, is_business_enablement)
      raise ArgumentError, "owner and update_type are required"
    end

    [owner, update_type]
  end

  sig { returns(T.nilable(String)) }
  def self.prefix
    name
  end

  sig { params(business: T.nilable(Business)).returns(String) }
  def self.job_id_business_prefix(business)
    business_id = business&.id || 0
    "#{self.prefix}.#{business_id}".underscore
  end

  sig { params(owner: Owner).returns(String) }
  def self.job_id_owner_prefix(owner)
    biz = owner.business

    if owner.user?
      # Set the business to the enterprise managed business if the feature is available
      ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(owner)
      biz = owner.enterprise_managed_business if ghas_for_users.feature_available?
    end

    "#{job_id_business_prefix(biz)}.#{owner.id}"
  end

  sig { params(owner: Owner, update_type: Symbol).returns(String) }
  def self.job_id(owner, update_type)
    "#{job_id_owner_prefix(owner)}.#{update_type}"
  end

  sig { params(owner: Owner, update_type: Symbol).returns(T.nilable(SecurityProductsEnablement::JobStatus)) }
  def self.status(owner, update_type)
    ActiveRecord::Base.connected_to(role: :writing) { SecurityProductsEnablement::JobStatus.find(job_id(owner, update_type)) }
  end

  sig do
    override
      .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
      .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
    owner = kwargs.fetch(:owner)
    update_type = kwargs.fetch(:update_type)

    base_repos_query(owner: owner, update_type: update_type)
      .where("id > ?", offset_id)
      .order(:id)
      .limit(1000)
  end

  sig { override.params(args: T.untyped, item: Repository, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs)
    repo = item
    actor = kwargs.fetch(:actor)
    owner = kwargs.fetch(:owner)
    update_type = kwargs.fetch(:update_type)
    business_enable = kwargs.fetch(:business_enable, false)

    log_with_timing({ "gh.repo.id": repo.id, "gh.repo.name": repo.name }) do
      GitHub.dogstats.distribution_time("#{T.must(self.class.name).underscore}.process_batch.repo.dist", tags: all_stats_tags) do
        result = Repository.throttle_writes_with_retry do
          SecurityProduct::ServiceManager
            .new(repo)
            .toggle_services_with_form_inputs(actor, params: get_toggle_services_params(update_type, business_enable, repo, owner))
        end

        if result.error?
          emit_enablement_outcome(update_type, false)
          GitHub.logger.error(result.error)
          raise ToggleServicesError.new if retry?(update_type, result.error)
        else
          emit_enablement_outcome(update_type, true)
        end
      end
    end
  end

  sig { override.params(args: T.untyped, is_last_job: T::Boolean, num_processed_items: Integer, kwargs: T.untyped).void }
  def post_process(*args, is_last_job:, num_processed_items:, **kwargs)
    initial_start = kwargs.fetch(:initial_start)
    num_in_sequence = kwargs.fetch(:num_in_sequence)
    sequence_num_processed_items = kwargs.fetch(:sequence_num_processed_items)
    owner = kwargs.fetch(:owner)
    update_type = kwargs.fetch(:update_type)
    is_business_enablement = kwargs.fetch(:business_enable, false)
    parent_initial_sequence_id = kwargs.fetch(:parent_initial_sequence_id, nil)
    business_enablement_started_at = kwargs.fetch(:business_enablement_started_at, nil)
    initially_enqueued_at = kwargs.fetch(:initially_enqueued_at, Time.current)

    emit_telemetry_on_long_running_sequence(initial_start:, owner:, update_type:)
    emit_enablement_time(is_last_job, is_business_enablement, initially_enqueued_at, update_type, parent_initial_sequence_id, business_enablement_started_at)

    GitHub.dogstats.distribution(
      "#{T.must(self.class.name).underscore}.num_repos_processed.dist",
      num_processed_items,
      tags: all_stats_tags
    )

    GitHub.logger.info("processed batch", {
      "gh.security_products.job.is_last_job": is_last_job,
      "gh.security_products.job.repos_processed": num_processed_items,
      "gh.security_products.job.sequence_repos_processed": sequence_num_processed_items,
      "gh.security_products.job.sequence_duration_sec": Time.current.utc - initial_start
    })
  end

  sig { override.params(args: T.untyped, kwargs: T.untyped).void }
  def finalize_sequence(*args, **kwargs)
    owner = kwargs.fetch(:owner)
    update_type = kwargs.fetch(:update_type)
    emit_backfill_group_request = kwargs.fetch(:emit_backfill_group_request, EMIT_BACKFILL_GROUP_REQUEST_DEFAULT)
    sequence_num_processed_items = kwargs.fetch(:sequence_num_processed_items)

    log_with_timing({ "code.function": __method__ }) do
      delete_long_running_sequence(owner, update_type)

      should_emit_backfill = sequence_num_processed_items > 0
      should_emit_backfill &&= [:secret_scanning_enable_all, :secret_scanning_disable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all, :secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all].include?(update_type)
      should_emit_backfill &&= emit_backfill_group_request
      should_start_backfill = [:secret_scanning_enable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_lower_confidence_patterns_enable_all].include?(update_type)
      group_type = :FULL
      if [:secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all].include?(update_type)
        group_type = :GENERIC_SECRETS
      elsif [:secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all].include?(update_type)
        group_type = :LOW_CONFIDENCE_PATTERN
      end
      if should_emit_backfill
        GitHub.logger.info("publishing TSS backfill message")
        GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
          action:  should_start_backfill ? :START : :CANCEL,
          owner: owner,
          requested_at: Time.current.utc,
          type: group_type,
          feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags
        })
      end
    end
  end

  sig { override.returns(Float) }
  def timeout_sec
    overwrite_sec = GitHub
      .flipper[:security_analysis_settings_update_job_runtime_cutoff_sec_overwrite]
      .percentage_of_actors_value

    return super if overwrite_sec == 0

    overwrite_sec
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    kwargs = arguments[0] || {}
    actor = kwargs.fetch(:actor)
    owner = kwargs.fetch(:owner)
    update_type = kwargs.fetch(:update_type)
    initial_start = kwargs.fetch(:initial_start, Time.current.utc)
    offset_id = kwargs.fetch(:offset_id, 0)
    num_in_sequence = kwargs.fetch(:num_in_sequence, 1)
    sequence_id = kwargs.fetch(:sequence_id, initial_sequence_id)

    ctx = {
      "enduser.id": actor.display_login,
      "gh.enduser.id": actor.id,
      "gh.enduser.login": actor.display_login,
      "gh.security_products.job.emit_backfill_group_request": kwargs.fetch(:emit_backfill_group_request, EMIT_BACKFILL_GROUP_REQUEST_DEFAULT),
      "gh.security_products.job.initial_start": initial_start,
      "gh.security_products.job.offset_id": offset_id,
      "gh.security_products.job.num_applicable_repos": num_total_applicable_repos(owner: owner, update_type: update_type),
      "gh.security_products.job.num_in_sequence": num_in_sequence,
      "gh.security_products.job.update_type": update_type,
      "gh.security_products.job.sequence_id": sequence_id
    }

    tag_prefix = owner.organization? ? "gh.org" : "gh.user"
    ctx.merge!(
      "gh.owner.id": owner.id,
      "gh.owner.login": owner.display_login,
      "#{tag_prefix}.id": owner.id,
      "#{tag_prefix}.login": owner.display_login,
    )

    super.merge(ctx)
  end

  sig { override.returns(T::Array[String]) }
  def stats_tags
    tags = []
    owner = arguments.dig(0, :owner)
    update_type = arguments.dig(0, :update_type)

    tags << "owner_is_org:#{owner.organization?}" if owner.present?
    tags << "update_type:#{update_type}" if update_type.present?
    tags
  end

  sig { params(owner: Owner, update_type: Symbol).returns(SecurityProductsEnablement::JobStatus) }
  def upsert_job_status(owner, update_type)
    job_status = self.class.status(owner, update_type)
    return job_status if job_status&.pending? || job_status&.started?

    SecurityProductsEnablement::JobStatus.create({ id: self.class.job_id(owner, update_type), ttl: 10.minutes })
  end

  sig { params(parent_initial_sequence_id: T.nilable(String), is_business_enablement: T.nilable(T::Boolean)).returns(T.any(T::Boolean, T.nilable(Integer))) }
  def self.decrement_business_enablement_counter(parent_initial_sequence_id, is_business_enablement)
    if !is_business_enablement
      return nil
    end
    if parent_initial_sequence_id.nil?
      return nil
    end
    result = ActiveRecord::Base.connected_to(role: :writing) do
      begin
        SecurityProductsEnablement::KV.store.increment(SecurityAnalysisSettingsBatchUpdateBusinessJob.business_enablement_kv_key(parent_initial_sequence_id), amount: -1, expires: 3.hours.from_now)
      rescue GitHub::KV::UnavailableError => e
        GitHub.logger.error(e)
      rescue => e # rubocop:disable Lint/GenericRescue
        GitHub.logger.error(e)
      end
    end
  end

  protected

  sig do
    params(
      is_last_job: T::Boolean,
      is_business_enablement: T::Boolean,
      this_job_initially_enqueued_at: T.nilable(Time),
      update_type: Symbol,
      parent_initial_sequence_id: T.nilable(String),
      business_enablement_started_at: T.nilable(Time)
    ).void
  end
  def emit_enablement_time(is_last_job, is_business_enablement, this_job_initially_enqueued_at, update_type, parent_initial_sequence_id, business_enablement_started_at)
    unless is_last_job
      return
    end

    ## Last job organization enablement

    unless is_business_enablement
      if this_job_initially_enqueued_at.nil?
        return
      end
      elapsed = Time.now - this_job_initially_enqueued_at
      GitHub.dogstats.distribution("ghas.org.enablement_time", GitHub::Dogstats.duration(this_job_initially_enqueued_at), tags: ["update_type:#{update_type}"])
      return
    end

    ## Last job for business enablement

    if business_enablement_started_at.nil?
      return
    end

    result = SecurityAnalysisSettingsUpdateJob.decrement_business_enablement_counter(parent_initial_sequence_id, is_business_enablement)

    if result == 0
      elapsed = Time.now - business_enablement_started_at
      GitHub.dogstats.distribution("ghas.business.enablement_time", GitHub::Dogstats.duration(business_enablement_started_at), tags: ["update_type:#{update_type}"])
    end
  end

  sig { params(update_type: Symbol, did_succeed: T::Boolean).void }
  def emit_enablement_outcome(update_type, did_succeed)
    GitHub.dogstats.increment("ghas.business.enablement_result", tags: all_stats_tags + ["update_type:#{update_type}", "success:#{did_succeed}"])
  end

  sig { params(owner: Owner, update_type: Symbol).returns(ActiveRecord::Relation) }
  def base_repos_query(owner:, update_type:)
    return @_base_repos_query if defined?(@_base_repos_query)

    case owner
    when Organization
      owner_type = :organization
    when User
      owner_type = :user
    end

    repos = Repository.active.where(owner_id: owner.id)

    case update_type
    when :dependency_graph_enable_all, :dependency_graph_disable_all
      repos = repos.private_scope unless GitHub.enterprise?
    when :advanced_security_enable_all, :advanced_security_disable_all
      repos = repos.can_enable_advanced_security(owner_type)
    when :auto_codeql_enable_all, :auto_codeql_enable_all_extended, :auto_codeql_disable_all
      repos = repos.not_archived_scope
    end

    @_base_repos_query = repos
  end

  # Emit telemetry on the first job in a sequence that takes longer than 1 hour.
  sig { params(initial_start: Time, owner: Owner, update_type: Symbol).void }
  def emit_telemetry_on_long_running_sequence(initial_start:, owner:, update_type:)
    log_with_timing({ "code.function": __method__ }) do
      return unless long_running_sequence?(initial_start)
      return if long_running_sequence_set?(owner, update_type)

      GitHub.dogstats.increment(
        "#{T.must(self.class.name).underscore}.emit_telemetry_on_long_running_sequence",
        tags: all_stats_tags
      )
      set_long_running_sequence(owner, update_type)
    end
  end

  sig { params(update_type: Symbol, business_enable: T::Boolean, repo: Repository, owner: User).returns(T::Hash[Symbol, String]) }
  def get_toggle_services_params(update_type, business_enable, repo, owner)
    toggle_services_params = {}

    case update_type
    when :innersource_advisories_enable_all
      toggle_services_params[:innersource_advisories_enabled] = "1"
    when :innersource_advisories_disable_all
      toggle_services_params[:innersource_advisories_enabled] = "0"
    when :private_vulnerability_reporting_enable_all
      toggle_services_params[:private_vulnerability_reporting_enabled] = "1"
    when :private_vulnerability_reporting_disable_all
      toggle_services_params[:private_vulnerability_reporting_enabled] = "0"
    when :dependency_graph_enable_all
      toggle_services_params[:dependency_graph_enabled] = "1"
    when :dependency_graph_disable_all
      toggle_services_params[:dependency_graph_enabled] = "0"
    when :security_alerts_enable_all
      toggle_services_params[:vulnerability_alerts_enabled] = "1"
    when :security_alerts_disable_all
      toggle_services_params[:vulnerability_alerts_enabled] = "0"
    when :vulnerability_updates_enable_all
      toggle_services_params[:vulnerability_updates_enabled] = "1"
    when :vulnerability_updates_disable_all
      toggle_services_params[:vulnerability_updates_enabled] = "0"
    when :vulnerability_updates_grouping_enable_all
      toggle_services_params[:vulnerability_updates_grouping_enabled] = "1"
    when :vulnerability_updates_grouping_disable_all
      toggle_services_params[:vulnerability_updates_grouping_enabled] = "0"
    when :dependabot_on_actions_enable_all
      toggle_services_params[:dependabot_on_actions_enabled] = "1"
    when :dependabot_on_actions_disable_all
      toggle_services_params[:dependabot_on_actions_enabled] = "0"
    when :dependabot_self_hosted_enable_all
      toggle_services_params[:dependabot_self_hosted_enabled] = "1"
    when :dependabot_self_hosted_disable_all
      toggle_services_params[:dependabot_self_hosted_enabled] = "0"
    when :dependabot_autofix_enable_all
      toggle_services_params[:dependabot_autofix_enabled] = "1"
    when :dependabot_autofix_disable_all
      toggle_services_params[:dependabot_autofix_enabled] = "0"
    when :auto_codeql_enable_all
      toggle_services_params[:auto_codeql_enabled] = "1"
      toggle_services_params[:bulk] = "1"
      toggle_services_params[:fail_on_manual_workflow] = "1"
      toggle_services_params[:skip_if_enabled] = "1"
    when :auto_codeql_enable_all_extended
      toggle_services_params[:auto_codeql_enabled] = "1"
      toggle_services_params[:bulk] = "1"
      toggle_services_params[:fail_on_manual_workflow] = "1"
      toggle_services_params[:auto_codeql_query_suite] = "extended"
      toggle_services_params[:skip_if_enabled] = "1"
    when :auto_codeql_disable_all
      toggle_services_params[:auto_codeql_enabled] = "0"
    when :secret_scanning_enable_all
      toggle_services_params[:token_scanning_enabled] = "1"
      # Repo backfills shouldn't be executed because this job will emit a BackfillGroupRequest hydro event.
      toggle_services_params[:skip_backfill_request] = "1"
    when :secret_scanning_disable_all
      toggle_services_params[:token_scanning_enabled] = "0"
    when :secret_scanning_validity_checks_enable_all
      toggle_services_params[:token_scanning_validity_checks_enabled] = "1"
    when :secret_scanning_validity_checks_disable_all
      toggle_services_params[:token_scanning_validity_checks_enabled] = "0"
    when :secret_scanning_lower_confidence_patterns_enable_all
      toggle_services_params[:token_scanning_lower_confidence_patterns_enabled] = "1"
      toggle_services_params[:skip_backfill_request] = "1"
    when :secret_scanning_lower_confidence_patterns_disable_all
      toggle_services_params[:token_scanning_lower_confidence_patterns_enabled] = "0"
    when :secret_scanning_generic_secrets_enable_all
      toggle_services_params[:token_scanning_generic_secrets_enabled] = "1"
      toggle_services_params[:skip_backfill_request] = "1"
    when :secret_scanning_generic_secrets_disable_all
      toggle_services_params[:token_scanning_generic_secrets_enabled] = "0"
    when :secret_scanning_push_protection_enable_all
      toggle_services_params[:token_scanning_push_protection_enabled] = "1"
    when :secret_scanning_push_protection_disable_all
      toggle_services_params[:token_scanning_push_protection_enabled] = "0"
    when :advanced_security_enable_all
      toggle_services_params[:advanced_security_enabled] = "1"
    when :advanced_security_disable_all
      toggle_services_params[:advanced_security_enabled] = "0"
    end

    if toggle_services_params[:vulnerability_updates_grouping_enabled] == "1" && owner.security_configurations_enabled?
      toggle_services_params[:vulnerability_updates_grouping_enabled] = "0" unless repo.vulnerability_updates_enabled?
    end

    # We need this param to be added here so that the toggle services method knows to override enforced configurations
    # on repositories because the enablement directive is coming from the business level enable/disable all page.
    if business_enable
      toggle_services_params[:enablement_action] = "enterprise_bulk_enablement"
    end

    toggle_services_params
  end

  sig do
    type_parameters(:U)
     .params(named_tags: T::Hash[T.untyped, T.untyped], blk: T.proc.returns(T.type_parameter(:U)))
     .returns(T.type_parameter(:U))
  end
  def log_with_timing(named_tags = {}, &blk)
    res = T.let(nil, T.untyped)

    GitHub.logger.with_named_tags(named_tags) do
      GitHub.logger.info("start")

      start = Time.current.utc
      res = yield
      duration_sec = Time.current.utc - start

      GitHub.logger.info("finish", { "http.server.duration_sec": duration_sec })
    end

    res
  end

  sig { params(initial_start: Time).returns(T::Boolean) }
  def long_running_sequence?(initial_start)
    elapsed_time_sec = Time.current.utc.to_i - initial_start.to_i
    sequence_runtime_hours = elapsed_time_sec / 60 / 60

    sequence_runtime_hours >= LONG_RUNNING_SEQUENCE_HOURS
  end

  sig { params(owner: Owner, update_type: Symbol).returns(Integer) }
  def num_total_applicable_repos(owner:, update_type:)
    base_repos_query(owner: owner, update_type: update_type).size
  end

  # Service-specific retry logic. Not all errors represent a failure state, not all failures are retryable.
  sig { params(update_type: Symbol, error: T.untyped).returns(T::Boolean) }
  def retry?(update_type, error)
    case update_type
    when :auto_codeql_enable_all, :auto_codeql_enable_all_extended, :auto_codeql_disable_all
      error.is_a?(CodeScanning::AutoCodeqlError) && error.twirp_error.nil?
    else
      false
    end
  end

  sig { params(owner: Owner, update_type: Symbol).void }
  def delete_long_running_sequence(owner, update_type)
    ApplicationRecord::Domain::KeyValues.throttle_writes_with_retry do
      SecurityProductsEnablement::KV.store.del(long_running_sequence_key(owner, update_type))
    end
  end

  sig { params(owner: Owner, update_type: Symbol).returns(String) }
  def long_running_sequence_key(owner, update_type)
    "long_running_sequence.#{self.class.job_id(owner, update_type)}"
  end

  sig { params(owner: Owner, update_type: Symbol).returns(T::Boolean) }
  def long_running_sequence_set?(owner, update_type)
    ApplicationRecord::Domain::KeyValues.throttle_with_retry do
      SecurityProductsEnablement::KV.store.exists(long_running_sequence_key(owner, update_type)).value { false }
    end
  end

  sig { params(owner: Owner, update_type: Symbol).void }
  def set_long_running_sequence(owner, update_type)
    ApplicationRecord::Domain::KeyValues.throttle_writes_with_retry do
      SecurityProductsEnablement::KV.store.set(long_running_sequence_key(owner, update_type), "true")
    end
  end
end
