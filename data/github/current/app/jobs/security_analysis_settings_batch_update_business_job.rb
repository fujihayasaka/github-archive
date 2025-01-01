# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Updates security and analysis settings for all repos in a business
class SecurityAnalysisSettingsBatchUpdateBusinessJob < TimedJob
  queue_as :security_analysis_settings_business_batched
  retry_on_dirty_exit
  BATCH_SIZE = 1000

  sig { override.returns(Float) }
  def timeout_sec
    3.minutes.to_f
  end

  sig do
    override
      .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
      .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
    owner = kwargs.fetch(:owner)
    entity_type = kwargs.fetch(:entity_type, :organization)

    case entity_type
    when :organization
      find_organizations(owner, offset_id, BATCH_SIZE)
    when :user
      find_users(owner, offset_id, BATCH_SIZE)
    else
      []
    end
  end

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs)
    owner = kwargs.fetch(:owner)
    update_type = kwargs.fetch(:update_type)
    actor_id = kwargs.fetch(:actor_id)
    actor = T.let(User.find(actor_id), User)

    if item.is_a?(Organization)
      return if update_type == :secret_scanning_enable_all && !item.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY)
      return if update_type == :advanced_security_enable_all && !item.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL)
    end

    ## Use the kv store to count how many child jobs are created by this business enablement job.
    ## The key is created with initial_sequence_id. As child jobs finish, they will decrement this counter.
    ## When the last child value will be 0, and it knows to emit a metric for business
    ## secret scanning enablement time. It can calculate this because we pass business_enablement_started_at
    ## to each child job.
    result = ActiveRecord::Base.connected_to(role: :writing) do
      begin
        SecurityProductsEnablement::KV.store.increment(SecurityAnalysisSettingsBatchUpdateBusinessJob.business_enablement_kv_key(initial_sequence_id), expires: 3.hours.from_now)
      rescue GitHub::KV::UnavailableError => e
        GitHub.logger.error(e)
      rescue => e # rubocop:disable Lint/GenericRescue
        GitHub.logger.error(e)
      end
    end

    initially_enqueued_at = kwargs.fetch(:initially_enqueued_at, Time.current)

    SecurityAnalysisSettingsUpdateJob.perform_later(
      actor: actor,
      emit_backfill_group_request: false,
      owner: item,
      update_type: update_type,
      ## The child jobs know:
      ##   - whether they are part of a larger business enablement job (business_enable)
      ##   - when the business enablement started (business_enablement_started_at)
      ##   - what the "job id" of it's parent (this job) is
      business_enable: true,
      business_enablement_started_at: initially_enqueued_at,
      parent_initial_sequence_id: initial_sequence_id
    )
  end

  sig { override.params(args: T.untyped, kwargs: T.untyped).void }
  def finalize_sequence(*args, **kwargs)
    update_type = kwargs.fetch(:update_type)
    owner = kwargs.fetch(:owner)

    backfill_request_allowed_update_types = [:secret_scanning_enable_all, :secret_scanning_disable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all, :secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all]
    should_start_backfill = [:secret_scanning_enable_all, :secret_scanning_generic_secrets_enable_all, :secret_scanning_lower_confidence_patterns_enable_all].include?(update_type)
    group_type = :FULL
    if [:secret_scanning_generic_secrets_enable_all, :secret_scanning_generic_secrets_disable_all].include?(update_type)
      group_type = :GENERIC_SECRETS
    elsif [:secret_scanning_lower_confidence_patterns_enable_all, :secret_scanning_lower_confidence_patterns_disable_all].include?(update_type)
      group_type = :LOW_CONFIDENCE_PATTERN
    end
    if backfill_request_allowed_update_types.include?(update_type)
      GitHub.logger.info("Sending backfill group request", "code.namespace": self.class.name, "code.function": __method__)
      GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
        owner: owner,
        action: should_start_backfill ? :START : :CANCEL,
        type: group_type,
        requested_at: Time.now.utc,
        feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags
      })
    end
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    kwargs = arguments[0] || {}
    owner = kwargs.fetch(:owner)
    update_type = kwargs.fetch(:update_type)
    actor_id = kwargs.fetch(:actor_id)
    initially_enqueued_at = kwargs.fetch(:initially_enqueued_at, Time.current)

    actor = T.let(User.find(actor_id), User)

    ctx = {
      "enduser.id": actor.display_login,
      "gh.enduser.id": actor_id,
      "gh.enduser.login": actor.display_login,
      "gh.business.id": owner.id,
      "gh.business.name": owner.name,
      "gh.security_products.job.update_type": update_type,
      "gh.security_products.job.initial_start": initially_enqueued_at,
    }
    super.merge(ctx)
  end

  sig { params(seq_id: String).returns(String) }
  def self.business_enablement_kv_key(seq_id)
    "business_enablement:counter:#{seq_id}"
  end

  private

  sig { params(owner: Business, offset_id: Integer, per_page: Integer).returns(T.all(T::Enumerable[T.untyped], Object)) }
  def find_organizations(owner, offset_id, per_page)
    owner.organizations
      .where("users.id > ?", offset_id)
      .order(:id)
      .limit(per_page)
  end

  sig { params(owner: Business, offset_id: Integer, per_page: Integer).returns(T.all(T::Enumerable[T.untyped], Object)) }
  def find_users(owner, offset_id, per_page)
    feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(owner)
    return [] unless feature.feature_available_for_user_repositories?

    feature.list_enterprise_users_offset(offset_id: offset_id, per_page: per_page)
  end
end
