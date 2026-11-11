# typed: strict
# frozen_string_literal: true

module Copilot
  class MemoryAdminDelete
    StatusContextValue = T.type_alias { T.any(String, Integer) }
    StatusContext = T.type_alias { T::Hash[Symbol, StatusContextValue] }
    LogValue = T.type_alias { T.any(String, Integer) }
    LogContext = T.type_alias { T::Hash[String, LogValue] }
    BillingEntityIds = T.type_alias { T::Hash[Symbol, T.nilable(Integer)] }

    FEATURE_FLAG = T.let(:copilot_memory_bulk_delete, Symbol)
    USER_SCOPED_MEMORY_FEATURE_FLAG = T.let(:copilot_feature_agentic_memory_user_scoped, Symbol)
    BUSINESS_OWNER_TYPE = T.let("Business", String)
    ORGANIZATION_OWNER_TYPE = T.let("Organization", String)
    JOB_STATUS_TTL = T.let(7.days, ActiveSupport::Duration)
    QUEUED_STALE_AFTER = T.let(10.minutes, ActiveSupport::Duration)
    HEARTBEAT_STALE_AFTER = T.let(10.minutes, ActiveSupport::Duration)
    LEASE_TTL = T.let(2.minutes, ActiveSupport::Duration)
    MAX_RUNTIME = T.let(45.0, Float)
    SEAT_PAGE_SIZE = T.let(500, Integer)
    MEMORY_PAGE_SIZE = T.let(100, Integer)
    MAX_USERS_PER_RUN = T.let(500, Integer)
    MAX_MEMORY_PAGES_PER_RUN = T.let(1_000, Integer)
    MAX_REENQUEUE_COUNT = T.let(10_000, Integer)
    MAX_STALLED_REENQUEUES = T.let(3, Integer)
    DELETE_REQUESTS_PER_SECOND = T.let(10, Integer)
    AUDIT_ACTIONS = T.let(%w[requested completed].freeze, T::Array[String])

    class OwnerNotFoundError < StandardError; end
    class ReenqueueLimitError < StandardError; end
    class StalledCheckpointError < StandardError; end
    class MissingBillingEntityError < StandardError; end
    class TargetUserNotFoundError < StandardError; end
    class StaleHeartbeatError < StandardError; end
    class StaleQueuedDeleteError < StandardError; end

    class MemoryPage < T::Struct
      const :deleted_count, Integer
      const :continuation_token, T.nilable(String)
    end

    class CreateStatusResult < T::Struct
      const :status, Copilot::MemoryAdminDeleteJobStatus
      const :created, T::Boolean
    end

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        actor: ::User,
        target_user: T.nilable(::User),
      )
        .returns(Copilot::MemoryAdminDeleteJobStatus)
    end
    def self.create_status(owner:, actor:, target_user: nil)
      create_status_result(owner: owner, actor: actor, target_user: target_user).status
    end

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        actor: ::User,
        target_user: T.nilable(::User),
      )
        .returns(CreateStatusResult)
    end
    def self.create_status_result(owner:, actor:, target_user: nil)
      current_status = status_for(owner: owner, target_user: target_user)
      if current_status && !current_status.finished?
        return CreateStatusResult.new(status: current_status, created: false)
      end

      current_status&.destroy
      status = Copilot::MemoryAdminDeleteJobStatus.create_once(
        id: status_id(owner: owner, target_user: target_user),
        state: "queued",
        ttl: JOB_STATUS_TTL,
        context: context_for(owner: owner, actor: actor, target_user: target_user),
      )
      unless status
        current_status = status_for(owner: owner, target_user: target_user)
        if current_status
          return CreateStatusResult.new(status: current_status, created: false)
        end

        raise StandardError, "failed to claim Copilot Memory admin delete for #{owner_type_for(owner)} #{owner.id}"
      end

      instrument("requested", status)
      CreateStatusResult.new(status: status, created: true)
    end

    sig { params(owner: T.any(::Business, ::Organization)).returns(T::Boolean) }
    def self.enabled_for?(owner:)
      case owner
      when ::Business
        owner.feature_flag_enabled?(FEATURE_FLAG, default: false)
      when ::Organization
        return true if owner.feature_flag_enabled?(FEATURE_FLAG, default: false)

        business = owner.business
        return false unless business

        business.feature_flag_enabled?(FEATURE_FLAG, default: false)
      else
        T.absurd(owner)
      end
    end

    sig { params(owner: T.any(::Business, ::Organization), actor: ::User).returns(T::Boolean) }
    def self.delete_allowed?(owner:, actor:)
      return false unless enabled_for?(owner: owner)
      return false unless user_scoped_memories_enabled?(owner: owner, actor: actor)
      return false unless memory_policy_visible_for_owner?(owner)
      return false unless tenant_for_owner(owner)

      case owner
      when ::Business
        true
      when ::Organization
        copilot_organization = Copilot::Organization.new(owner)
        return false if copilot_organization.business_trial&.has_trial?

        copilot_organization.copilot_billable?
      else
        T.absurd(owner)
      end
    end

    sig { params(owner: T.any(::Business, ::Organization)).returns(T::Boolean) }
    def self.memory_policy_visible_for_owner?(owner)
      case owner
      when ::Business
        Copilot::Policies::Memory.available_for?(Copilot::Business.new(owner))
      when ::Organization
        Copilot::Policies::Memory.viewable_by_org?(Copilot::Organization.new(owner))
      else
        T.absurd(owner)
      end
    end
    private_class_method :memory_policy_visible_for_owner?

    sig { params(owner: T.any(::Business, ::Organization), actor: ::User).returns(T::Boolean) }
    def self.user_scoped_memories_enabled?(owner:, actor:)
      case owner
      when ::Business
        owner.feature_flag_enabled?(USER_SCOPED_MEMORY_FEATURE_FLAG, default: false) ||
          actor.feature_flag_enabled?(USER_SCOPED_MEMORY_FEATURE_FLAG, default: false) ||
          FeatureFlag.vexi.enabled?(USER_SCOPED_MEMORY_FEATURE_FLAG, owner, actor, default: false)
      when ::Organization
        owner.feature_flag_enabled?(USER_SCOPED_MEMORY_FEATURE_FLAG, default: false) ||
          owner.business&.feature_flag_enabled?(USER_SCOPED_MEMORY_FEATURE_FLAG, default: false) ||
          actor.feature_flag_enabled?(USER_SCOPED_MEMORY_FEATURE_FLAG, default: false) ||
          FeatureFlag.vexi.enabled?(USER_SCOPED_MEMORY_FEATURE_FLAG, owner, actor, default: false)
      else
        T.absurd(owner)
      end
    end

    sig { params(owner: T.any(::Business, ::Organization), target_user: ::User).returns(T::Boolean) }
    def self.target_user_allowed?(owner:, target_user:)
      licensed_seats_scope(owner)
        .where(assigned_user_id: target_user.id)
        .exists?
    end

    sig { params(owner: T.any(::Business, ::Organization), target_user: T.nilable(::User)).returns(String) }
    def self.status_id(owner:, target_user: nil)
      status_scope = "#{owner_type_for(owner).underscore}:#{owner.id}"
      status_scope = "#{status_scope}:user:#{target_user.id}" if target_user
      "#{Copilot::MemoryAdminDeleteJobStatus::PREFIX}_#{status_scope}"
    end

    sig { params(status_id: String).returns(T.nilable(Copilot::MemoryAdminDeleteJobStatus)) }
    def self.status(status_id)
      Copilot::MemoryAdminDeleteJobStatus.find_for_delete(status_id)
    end

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        target_user: T.nilable(::User),
      ).returns(T.nilable(Copilot::MemoryAdminDeleteJobStatus))
    end
    def self.status_for(owner:, target_user: nil)
      status = status(status_id(owner: owner, target_user: target_user))
      return unless status && valid_owner?(status: status, owner: owner, target_user: target_user)

      mark_stale!(status) if stale?(status)
      status
    end

    sig do
      params(
        status: Copilot::MemoryAdminDeleteJobStatus,
        owner: T.any(::Business, ::Organization),
        target_user: T.nilable(::User),
      ).returns(T::Boolean)
    end
    def self.valid_owner?(status:, owner:, target_user: nil)
      context = status.context
      return false unless context

      stored_target_user_id = context_optional_integer_value(context, :target_user_id)
      expected_target_user_id = target_user&.id

      return false unless context_string_value(context, :owner_type) == owner_type_for(owner)
      return false unless context_integer_value(context, :owner_id) == owner.id

      stored_target_user_id == expected_target_user_id
    end

    sig do
      params(status: Copilot::MemoryAdminDeleteJobStatus)
        .returns(T.nilable(T.any(::Business, ::Organization)))
    end
    def self.owner_from_status(status)
      context = status.context
      return unless context

      owner_id = context_integer_value(context, :owner_id)
      case context_string_value(context, :owner_type)
      when BUSINESS_OWNER_TYPE
        ::Business.find_by(id: owner_id)
      when ORGANIZATION_OWNER_TYPE
        ::Organization.find_by(id: owner_id)
      end
    end

    sig { params(owner: T.any(::Business, ::Organization)).returns(String) }
    def self.owner_type_for(owner)
      case owner
      when ::Business
        BUSINESS_OWNER_TYPE
      when ::Organization
        ORGANIZATION_OWNER_TYPE
      else
        T.absurd(owner)
      end
    end

    sig { params(owner: T.any(::Business, ::Organization)).returns(String) }
    def self.label_for(owner)
      case owner
      when ::Business
        owner.slug
      when ::Organization
        owner.display_login
      else
        T.absurd(owner)
      end
    end
    private_class_method :label_for

    sig { params(owner: T.any(::Business, ::Organization)).returns(T.nilable(::Business)) }
    def self.tenant_for_owner(owner)
      case owner
      when ::Business
        owner
      when ::Organization
        owner.is_enterprise_managed? ? owner.enterprise_managed_business : owner.business
      else
        T.absurd(owner)
      end
    end

    sig { params(status_id: String).returns(T.nilable(String)) }
    def self.acquire_lease(status_id)
      token = SecureRandom.uuid
      expires_at = Time.now + LEASE_TTL
      created = ActiveRecord::Base.connected_to(role: :writing) do
        Copilot::KV.store.setnx(lease_key(status_id), token, expires: expires_at)
      end

      created ? token : nil
    end

    sig { params(status_id: String, token: String).void }
    def self.release_lease(status_id, token:)
      key = lease_key(status_id)
      stored_token = Copilot::KV.store.get(key).value { nil }
      return unless stored_token == token

      ActiveRecord::Base.connected_to(role: :writing) do
        Copilot::KV.store.del(key)
      end
    rescue StandardError => error
      GitHub.logger.warn(
        "Copilot memory admin delete lease release failed",
        "gh.copilot_memory_admin_delete.status_id" => status_id,
        "gh.error.class" => error.class.name,
      )
    end

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(T::Boolean) }
    def self.process(status)
      return false if status.success? || status.error?

      owner = owner_from_status(status)
      unless owner
        failed!(status, error: OwnerNotFoundError.new("Copilot Memory admin delete owner not found"))
        return false
      end

      begin
        ensure_billing_entity!(owner)
      rescue MissingBillingEntityError => error
        failed!(status, error: error)
        return false
      end
      unless target_user_valid_for_status?(status: status, owner: owner)
        failed!(status, error: TargetUserNotFoundError.new("Copilot Memory admin delete target user not found"))
        return false
      end

      started!(status) unless status.started?
      context = status_context(status)
      end_at = Time.now.to_f + MAX_RUNTIME
      pages_processed = T.let(0, Integer)
      users_processed = T.let(0, Integer)
      throttler = GitHub::Throttler::PerSecond.new(per_second: DELETE_REQUESTS_PER_SECOND)

      loop do
        break unless processing_budget_remaining?(
          end_at: end_at,
          pages_processed: pages_processed,
          users_processed: users_processed,
        )

        current_user_id = context_optional_integer_value(context, :current_user_id)
        if current_user_id
          current_page = delete_memory_page(
            owner: owner,
            user_id: current_user_id,
            context: context,
            throttler: throttler,
          )
          apply_memory_page_checkpoint!(status: status, context: context, page: current_page, user_id: current_user_id)
          pages_processed += 1
          users_processed += 1 unless current_page.continuation_token.present?
          next
        end

        user_ids = next_user_ids(owner: owner, context: context)
        if user_ids.empty?
          completed!(status)
          return false
        end

        user_ids.each do |user_id|
          break unless processing_budget_remaining?(
            end_at: end_at,
            pages_processed: pages_processed,
            users_processed: users_processed,
          )

          user_page = delete_memory_page(owner: owner, user_id: user_id, context: context, throttler: throttler)
          apply_memory_page_checkpoint!(status: status, context: context, page: user_page, user_id: user_id)
          pages_processed += 1
          users_processed += 1 unless user_page.continuation_token.present?
          break if user_page.continuation_token.present?
        end
      end

      prepare_reenqueue!(status)
    end

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).void }
    def self.started!(status)
      context = status_context(status)
      now = Time.now.utc.iso8601
      context[:started_at] = now if context[:started_at].blank?
      context[:heartbeat_at] = now
      status.context = context
      status.started!
      instrument("started", status)
    end

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).void }
    def self.completed!(status)
      context = status_context(status)
      context[:completed_at] = Time.now.utc.iso8601
      status.context = context
      status.success!
      instrument("completed", status)
    end

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus, error: Exception, report: T::Boolean).void }
    def self.failed!(status, error:, report: true)
      context = status_context(status)
      context[:error_class] = error.class.name.to_s
      context[:error_message] = error.message
      context[:completed_at] = Time.now.utc.iso8601
      status.context = context
      Failbot.report(error, log_context(status)) if report
      status.error!(failure_message(error))
      instrument("failed", status)
    end

    sig { params(status_id: String, error: Exception).void }
    def self.dirty_exit_failed!(status_id, error:)
      status = status(status_id)
      return unless status
      return if status.success? || status.error?

      failed!(status, error: error)
    end

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        actor: ::User,
        target_user: T.nilable(::User),
      ).returns(StatusContext)
    end
    def self.context_for(owner:, actor:, target_user: nil)
      requested_at = Time.now.utc
      context = T.let({
        owner_type: owner_type_for(owner),
        owner_id: owner.id,
        owner_label: label_for(owner),
        actor_id: actor.id,
        actor_login: actor.display_login,
        requested_at: requested_at.iso8601,
        consistency_cutoff: requested_at.iso8601,
      }, StatusContext)
      if target_user
        context[:target_user_id] = target_user.id
        context[:target_user_login] = target_user.display_login
      end
      context
    end
    private_class_method :context_for

    sig do
      params(
        end_at: Float,
        pages_processed: Integer,
        users_processed: Integer,
      ).returns(T::Boolean)
    end
    def self.processing_budget_remaining?(end_at:, pages_processed:, users_processed:)
      Time.now.to_f < end_at &&
        pages_processed < MAX_MEMORY_PAGES_PER_RUN &&
        users_processed < MAX_USERS_PER_RUN
    end
    private_class_method :processing_budget_remaining?

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        context: StatusContext,
      ).returns(T::Array[Integer])
    end
    def self.next_user_ids(owner:, context:)
      target_user_id = context_optional_integer_value(context, :target_user_id)
      if target_user_id
        return [] if context_integer_value(context, :seat_cursor) >= target_user_id

        return [target_user_id]
      end

      licensed_user_ids(
        owner: owner,
        after_user_id: context_integer_value(context, :seat_cursor),
        limit: SEAT_PAGE_SIZE,
      )
    end
    private_class_method :next_user_ids

    sig do
      params(
        status: Copilot::MemoryAdminDeleteJobStatus,
        owner: T.any(::Business, ::Organization),
      ).returns(T::Boolean)
    end
    def self.target_user_valid_for_status?(status:, owner:)
      target_user_id = context_optional_integer_value(status_context(status), :target_user_id)
      return true unless target_user_id

      licensed_seats_scope(owner)
        .where(assigned_user_id: target_user_id)
        .exists?
    end
    private_class_method :target_user_valid_for_status?

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        user_id: Integer,
        context: StatusContext,
        throttler: GitHub::Throttler::PerSecond,
      ).returns(MemoryPage)
    end
    def self.delete_memory_page(owner:, user_id:, context:, throttler:)
      billing_entity_ids = ensure_billing_entity!(owner)
      response = T.let(
        nil,
        T.nilable(Twirp::ClientResp[Sweagentd::JobsAPI::V1::DeleteUserMemoriesForBillingEntityResponse]),
      )
      throttler.throttle do
        response = GitHub::Sweagentd::Client::Jobs.new.delete_user_memories_for_billing_entity(
          Sweagentd::JobsAPI::V1::DeleteUserMemoriesForBillingEntityRequest.new(
            user_id: user_id,
            organization_id: (billing_entity_ids.fetch(:billing_organization_id) || 0),
            enterprise_id: (billing_entity_ids.fetch(:billing_enterprise_id) || 0),
            limit: MEMORY_PAGE_SIZE,
            continuation_token: context_string_value(context, :current_memory_continuation_token),
            snapshot_time: protobuf_timestamp(delete_snapshot_time(context)),
          ),
        )
      end
      response = T.must(response)
      data = T.let(
        response.data,
        T.nilable(Sweagentd::JobsAPI::V1::DeleteUserMemoriesForBillingEntityResponse),
      )
      unless data
        return MemoryPage.new(deleted_count: 0, continuation_token: nil) if response.error&.code == :not_found

        raise GitHub::Sweagentd::Client::Jobs::ApiError,
          "Empty data from sweagentd-jobs-service delete_user_memories_for_billing_entity"
      end

      MemoryPage.new(
        deleted_count: data.deleted_count.to_i,
        continuation_token: data.continuation_token.presence,
      )
    end
    private_class_method :delete_memory_page

    sig do
      params(
        status: Copilot::MemoryAdminDeleteJobStatus,
        context: StatusContext,
        page: MemoryPage,
        user_id: Integer,
      ).void
    end
    def self.apply_memory_page_checkpoint!(status:, context:, page:, user_id:)
      now = Time.now.utc.iso8601
      context[:heartbeat_at] = now
      context[:page_count] = context_integer_value(context, :page_count) + 1
      context[:memory_count] = context_integer_value(context, :memory_count) + page.deleted_count
      context[:query_fingerprint] = query_fingerprint(context: context, user_id: user_id)

      if page.continuation_token.present?
        context[:current_user_id] = user_id
        context[:current_memory_continuation_token] = T.must(page.continuation_token)
      else
        context.delete(:current_user_id)
        context.delete(:current_memory_continuation_token)
        context[:seat_cursor] = user_id
        context[:user_count] = context_integer_value(context, :user_count) + 1
      end

      status.context = context
      status.save
    end
    private_class_method :apply_memory_page_checkpoint!

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(T::Boolean) }
    def self.prepare_reenqueue!(status)
      context = status_context(status)
      reenqueue_count = context_integer_value(context, :reenqueue_count) + 1
      if reenqueue_count > MAX_REENQUEUE_COUNT
        failed!(status, error: ReenqueueLimitError.new("Copilot Memory admin delete exceeded re-enqueue limit"))
        return false
      end

      fingerprint = checkpoint_fingerprint(context)
      stalled_count = if context_string_value(context, :last_reenqueue_fingerprint) == fingerprint
        context_integer_value(context, :stalled_reenqueue_count) + 1
      else
        0
      end
      if stalled_count > MAX_STALLED_REENQUEUES
        failed!(
          status,
          error: StalledCheckpointError.new("Copilot Memory admin delete checkpoint stopped making progress"),
        )
        return false
      end

      context[:reenqueue_count] = reenqueue_count
      context[:last_reenqueue_fingerprint] = fingerprint
      context[:stalled_reenqueue_count] = stalled_count
      context[:heartbeat_at] = Time.now.utc.iso8601
      status.context = context
      status.save
      true
    end
    private_class_method :prepare_reenqueue!

    sig { params(owner: T.any(::Business, ::Organization)).returns(BillingEntityIds) }
    def self.ensure_billing_entity!(owner)
      billing_entity_ids = billing_entity_ids(owner)
      if billing_entity_ids[:billing_organization_id].nil? && billing_entity_ids[:billing_enterprise_id].nil?
        raise MissingBillingEntityError, "Copilot Memory admin delete owner has no billing entity"
      end

      billing_entity_ids
    end
    private_class_method :ensure_billing_entity!

    sig { params(owner: T.any(::Business, ::Organization)).returns(BillingEntityIds) }
    def self.billing_entity_ids(owner)
      case owner
      when ::Business
        {
          billing_organization_id: nil,
          billing_enterprise_id: owner.id,
        }
      when ::Organization
        {
          billing_organization_id: owner.id,
          billing_enterprise_id: owner.business&.id,
        }
      else
        T.absurd(owner)
      end
    end
    private_class_method :billing_entity_ids

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        after_user_id: Integer,
        limit: Integer,
      ).returns(T::Array[Integer])
    end
    def self.licensed_user_ids(owner:, after_user_id:, limit:)
      licensed_seats_scope(owner)
        .where("assigned_user_id > ?", after_user_id)
        .where.not(assigned_user_id: nil)
        .distinct
        .order(:assigned_user_id)
        .limit(limit)
        .pluck(:assigned_user_id)
        .map(&:to_i)
    end
    private_class_method :licensed_user_ids

    sig { params(owner: T.any(::Business, ::Organization)).returns(ActiveRecord::Relation) }
    def self.licensed_seats_scope(owner)
      case owner
      when ::Business
        Copilot::Seat.all_active_seats_in_business(owner)
      when ::Organization
        Copilot::Seat
          .for_organization(owner)
          .joins(:seat_assignment)
          .where(copilot_seat_assignments: { access_revoked_at: nil })
      else
        T.absurd(owner)
      end
    end
    private_class_method :licensed_seats_scope

    sig { params(context: StatusContext, user_id: Integer).returns(String) }
    def self.query_fingerprint(context:, user_id:)
      [
        context_string_value(context, :owner_type),
        context_string_value(context, :owner_id),
        user_id,
        context_string_value(context, :consistency_cutoff),
        MEMORY_PAGE_SIZE,
      ].join(":")
    end
    private_class_method :query_fingerprint

    sig { params(context: StatusContext).returns(String) }
    def self.checkpoint_fingerprint(context)
      [
        context_integer_value(context, :seat_cursor),
        context_integer_value(context, :current_user_id),
        context_string_value(context, :current_memory_continuation_token),
        context_integer_value(context, :page_count),
      ].join(":")
    end
    private_class_method :checkpoint_fingerprint

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus, key: Symbol).returns(Integer) }
    def self.context_integer(status, key)
      context_integer_value(status_context(status), key)
    end
    private_class_method :context_integer

    sig { params(context: StatusContext, key: Symbol).returns(Integer) }
    def self.context_integer_value(context, key)
      value = context.fetch(key, 0)
      value.to_i
    end
    private_class_method :context_integer_value

    sig { params(context: StatusContext, key: Symbol).returns(T.nilable(Integer)) }
    def self.context_optional_integer_value(context, key)
      value = context.fetch(key, nil)
      return if value.blank?

      value.to_i
    end
    private_class_method :context_optional_integer_value

    sig { params(context: StatusContext, key: Symbol).returns(String) }
    def self.context_string_value(context, key)
      context.fetch(key, nil).to_s
    end
    private_class_method :context_string_value

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(StatusContext) }
    def self.status_context(status)
      status.context || {}
    end
    private_class_method :status_context

    sig { params(status_id: String).returns(String) }
    def self.lease_key(status_id)
      "copilot-memory-admin-delete:lease:#{status_id}"
    end
    private_class_method :lease_key

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(T::Boolean) }
    def self.stale?(status)
      return stale_queued?(status) if status.queued?
      return stale_started?(status) if status.started?

      false
    end
    private_class_method :stale?

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).void }
    def self.mark_stale!(status)
      error = if status.queued?
        StaleQueuedDeleteError.new("Copilot Memory admin delete did not start")
      else
        StaleHeartbeatError.new("Copilot Memory admin delete heartbeat expired")
      end
      failed!(status, error: error)
    end
    private_class_method :mark_stale!

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(T::Boolean) }
    def self.stale_queued?(status)
      requested_at = context_time(status, :requested_at)
      return false unless requested_at

      requested_at < QUEUED_STALE_AFTER.ago
    end
    private_class_method :stale_queued?

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(T::Boolean) }
    def self.stale_started?(status)
      heartbeat_at = context_time(status, :heartbeat_at) || context_time(status, :started_at)
      return false unless heartbeat_at

      heartbeat_at < HEARTBEAT_STALE_AFTER.ago
    end
    private_class_method :stale_started?

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus, key: Symbol).returns(T.nilable(Time)) }
    def self.context_time(status, key)
      stored_at = context_string(status, key)
      return if stored_at.blank?

      Time.iso8601(stored_at)
    rescue ArgumentError
      nil
    end
    private_class_method :context_time

    sig { params(event: String, status: Copilot::MemoryAdminDeleteJobStatus).void }
    def self.instrument(event, status)
      result = event == "failed" ? "error" : "success"
      payload = log_context(status).merge(
        "gh.copilot_memory_admin_delete.action" => event,
        "gh.copilot_memory_admin_delete.result" => result,
      )
      if result == "error"
        GitHub.logger.error("Copilot memory admin delete #{event}", payload)
      else
        GitHub.logger.info("Copilot memory admin delete #{event}", payload)
      end
      context = status.context || {}
      scope = context.key?(:target_user_id) ? "user" : "all"

      GitHub.dogstats.increment("copilot_memory.admin_delete.#{event}", tags: [
        "owner_type:#{context[:owner_type].to_s.underscore}",
        "scope:#{scope}",
        "result:#{result}",
      ])
      instrument_terminal_duration(status, result: result) if event == "completed" || event == "failed"

      return unless AUDIT_ACTIONS.include?(event)

      audit_prefix = context[:owner_type] == "Business" ? "business" : "org"
      payload = {
        actor: context[:actor_login],
        actor_id: context[:actor_id],
        copilot_memory_delete_id: status.id,
        copilot_memory_delete_scope: scope,
        target_user: context[:target_user_login],
        target_user_id: context[:target_user_id],
        requested_at: context[:requested_at],
      }

      if context[:owner_type] == "Business"
        payload[:business] = context[:owner_label]
        payload[:business_id] = context[:owner_id]
      else
        payload[:org] = context[:owner_label]
        payload[:org_id] = context[:owner_id]
      end

      GitHub.instrument("#{audit_prefix}.copilot_memory_admin_delete_#{event}", payload)
    end
    private_class_method :instrument

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus, result: String).void }
    def self.instrument_terminal_duration(status, result:)
      duration = duration_ms(status)
      return if duration.nil?

      context = status_context(status)
      GitHub.dogstats.distribution("copilot_memory.admin_delete.duration_ms", duration, tags: [
        "owner_type:#{context_string_value(context, :owner_type).underscore}",
        "scope:#{context.key?(:target_user_id) ? 'user' : 'all'}",
        "result:#{result}",
      ])
    end
    private_class_method :instrument_terminal_duration

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(T.nilable(Float)) }
    def self.duration_ms(status)
      requested_at = context_time(status, :requested_at)
      completed_at = context_time(status, :completed_at)
      return if requested_at.nil? || completed_at.nil?

      GitHub::Dogstats.duration(requested_at, completed_at)
    end
    private_class_method :duration_ms

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus).returns(LogContext) }
    def self.log_context(status)
      context = {
        "gh.copilot_memory_admin_delete.owner_type" => context_string(status, :owner_type).underscore,
        "gh.copilot_memory_admin_delete.owner_id" => context_string(status, :owner_id),
        "gh.copilot_memory_admin_delete.actor_id" => context_string(status, :actor_id),
      }
      error_class = context_string(status, :error_class)
      context["gh.error.class"] = error_class if error_class.present?
      error_message = context_string(status, :error_message)
      context["gh.error.message"] = error_message if error_message.present?
      context
    end
    private_class_method :log_context

    sig { params(error: Exception).returns(String) }
    def self.failure_message(error)
      "#{error.class.name}: #{error.message}"
    end
    private_class_method :failure_message

    sig { params(status: Copilot::MemoryAdminDeleteJobStatus, key: Symbol).returns(String) }
    def self.context_string(status, key)
      value = status.context&.fetch(key, nil)
      value.to_s
    end
    private_class_method :context_string

    sig { params(context: StatusContext).returns(Time) }
    def self.delete_snapshot_time(context)
      timestamp = context_string_value(context, :consistency_cutoff)
      timestamp = context_string_value(context, :requested_at) if timestamp.blank?
      return Time.now.utc if timestamp.blank?

      Time.iso8601(timestamp)
    rescue ArgumentError
      Time.now.utc
    end
    private_class_method :delete_snapshot_time

    sig { params(time: Time).returns(Google::Protobuf::Timestamp) }
    def self.protobuf_timestamp(time)
      Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
    end
    private_class_method :protobuf_timestamp
  end
end
