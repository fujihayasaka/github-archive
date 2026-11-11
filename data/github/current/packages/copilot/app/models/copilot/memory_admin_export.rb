# typed: strict
# frozen_string_literal: true

require "base64"
require "sweagentd"

module Copilot
  class MemoryAdminExport
    StatusContextValue = T.type_alias { T.any(String, Integer) }
    StatusContext = T.type_alias { T::Hash[Symbol, StatusContextValue] }
    LogValue = T.type_alias { T.any(String, Integer) }
    LogContext = T.type_alias { T::Hash[String, LogValue] }
    BillingEntityIds = T.type_alias { T::Hash[Symbol, T.nilable(Integer)] }
    MemorySourceRecordValue = T.type_alias { T.any(String, Integer, NilClass) }
    MemorySourceRecord = T.type_alias { T::Hash[Symbol, MemorySourceRecordValue] }
    MemoryRecordValue = T.type_alias do
      T.any(String, Integer, T::Boolean, NilClass, T::Array[String], MemorySourceRecord)
    end
    MemoryRecord = T.type_alias { T::Hash[Symbol, MemoryRecordValue] }
    MetadataValue = T.type_alias { T.any(String, Integer, T::Boolean, T::Hash[Symbol, Integer]) }

    CONTENT_TYPE = T.let("application/x-ndjson", String)
    FORMAT = T.let("jsonl", String)
    SCHEMA_VERSION = T.let(1, Integer)
    JOB_STATUS_TTL = T.let(2.hours, ActiveSupport::Duration)
    DOWNLOAD_URL_TTL = T.let(5.minutes, ActiveSupport::Duration)
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
    OUTPUT_BLOCK_TARGET_BYTES = T.let(4.megabytes, Integer)
    MAX_MEMORY_BLOCKS = T.let(49_999, Integer)
    MEMORY_FETCH_THROTTLE_SECONDS = T.let(0.01, Float)
    BLOCK_ID_WIDTH = T.let(12, Integer)
    METADATA_BLOCK_INDEX = T.let(0, Integer)
    FIRST_MEMORY_BLOCK_INDEX = T.let(1, Integer)
    STORAGE_PREFIX = T.let("copilot-memory-admin-exports", String)
    BLOB_RETENTION = T.let(3.days, ActiveSupport::Duration)
    BLOB_CLEANUP_DELETE_LIMIT = T.let(1_000, Integer)
    BLOB_CLEANUP_LIST_PAGE_SIZE = T.let(5_000, Integer)
    FEATURE_FLAG = T.let(:copilot_memory_admin_exports, Symbol)
    USER_SCOPED_MEMORY_FEATURE_FLAG = T.let(:copilot_feature_agentic_memory_user_scoped, Symbol)
    BUSINESS_OWNER_TYPE = T.let("Business", String)
    ORGANIZATION_OWNER_TYPE = T.let("Organization", String)
    AUDIT_SCOPE = T.let("user_scoped_memories", String)
    AUDIT_ACTIONS = T.let(%w[requested completed downloaded].freeze, T::Array[String])

    class MissingBlobError < StandardError; end
    class OwnerNotFoundError < StandardError; end
    class ReenqueueLimitError < StandardError; end
    class StalledCheckpointError < StandardError; end
    class BlockLimitError < StandardError; end
    class MissingBillingEntityError < StandardError; end
    class TargetUserNotFoundError < StandardError; end
    class StaleHeartbeatError < StandardError; end
    class StaleQueuedExportError < StandardError; end

    class MemoryPage < T::Struct
      const :records, T::Array[MemoryRecord]
      const :continuation_token, T.nilable(String)
    end

    class CreateStatusResult < T::Struct
      const :status, Copilot::MemoryAdminExportJobStatus
      const :created, T::Boolean
    end

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        actor: ::User,
        target_user: T.nilable(::User),
      )
        .returns(Copilot::MemoryAdminExportJobStatus)
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
      return CreateStatusResult.new(status: current_status, created: false) if current_status && reusable_status?(current_status)

      current_status&.destroy
      status = Copilot::MemoryAdminExportJobStatus.create_once(
        id: status_id(owner: owner, target_user: target_user),
        state: "queued",
        ttl: JOB_STATUS_TTL,
        context: context_for(owner: owner, actor: actor, target_user: target_user),
      )
      unless status
        current_status = status_for(owner: owner, target_user: target_user)
        return CreateStatusResult.new(status: current_status, created: false) if current_status && reusable_status?(current_status)

        raise StandardError, "failed to claim Copilot Memory admin export for #{owner_type_for(owner)} #{owner.id}"
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
    def self.export_allowed?(owner:, actor:)
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
      "#{Copilot::MemoryAdminExportJobStatus::PREFIX}_#{status_scope}"
    end

    sig { params(status_id: String).returns(T.nilable(Copilot::MemoryAdminExportJobStatus)) }
    def self.status(status_id)
      Copilot::MemoryAdminExportJobStatus.find_for_export(status_id)
    end

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        target_user: T.nilable(::User),
      ).returns(T.nilable(Copilot::MemoryAdminExportJobStatus))
    end
    def self.status_for(owner:, target_user: nil)
      status = status(status_id(owner: owner, target_user: target_user))
      return unless status && valid_owner?(status: status, owner: owner, target_user: target_user)

      mark_stale!(status) if stale?(status)
      status
    end

    sig do
      params(
        status: Copilot::MemoryAdminExportJobStatus,
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
      params(status: Copilot::MemoryAdminExportJobStatus)
        .returns(T.nilable(T.any(::Business, ::Organization)))
    end
    def self.owner_from_status(status)
      context = status.context
      return unless context

      owner_id = context[:owner_id].to_i
      case context[:owner_type]
      when BUSINESS_OWNER_TYPE
        ::Business.find_by(id: owner_id)
      when ORGANIZATION_OWNER_TYPE
        ::Organization.find_by(id: owner_id)
      end
    end

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
        "Copilot memory admin export lease release failed",
        "gh.copilot_memory_admin_export.status_id" => status_id,
        "gh.error.class" => error.class.name,
      )
    end

    sig do
      params(
        status: Copilot::MemoryAdminExportJobStatus,
        storage_client: Copilot::MemoryAdminExport::Storage,
      ).returns(T::Boolean)
    end
    def self.process(status, storage_client: storage)
      return false if status.success? || status.error?

      owner = owner_from_status(status)
      unless owner
        failed!(status, error: OwnerNotFoundError.new("Copilot Memory admin export owner not found"))
        return false
      end

      begin
        ensure_billing_entity!(owner)
      rescue MissingBillingEntityError => error
        failed!(status, error: error)
        return false
      end
      unless target_user_valid_for_status?(status: status, owner: owner)
        failed!(status, error: TargetUserNotFoundError.new("Copilot Memory admin export target user not found"))
        return false
      end
      started!(status) unless status.started?
      context = status_context(status)
      buffer = T.let(+"", String)
      end_at = Time.now.to_f + MAX_RUNTIME
      pages_processed = T.let(0, Integer)
      users_processed = T.let(0, Integer)

      loop do
        break unless processing_budget_remaining?(
          end_at: end_at,
          pages_processed: pages_processed,
          users_processed: users_processed,
        )

        current_user_id = context_optional_integer_value(context, :current_user_id)
        if current_user_id
          current_page = fetch_memory_page(
            owner: owner,
            user_id: current_user_id,
            context: context,
          )
          buffer = append_memory_page!(
            status: status,
            context: context,
            buffer: buffer,
            page: current_page,
            user_id: current_user_id,
            storage_client: storage_client,
          )
          pages_processed += 1
          users_processed += 1 unless current_page.continuation_token.present?
          next
        end

        user_ids = next_user_ids(owner: owner, context: context)
        if user_ids.empty?
          flush_output_block!(status: status, context: context, buffer: buffer, storage_client: storage_client)
          completed!(status, storage_client: storage_client)
          return false
        end

        user_ids.each do |user_id|
          break unless processing_budget_remaining?(
            end_at: end_at,
            pages_processed: pages_processed,
            users_processed: users_processed,
          )

          user_page = fetch_memory_page(
            owner: owner,
            user_id: user_id,
            context: context,
          )
          buffer = append_memory_page!(
            status: status,
            context: context,
            buffer: buffer,
            page: user_page,
            user_id: user_id,
            storage_client: storage_client,
          )
          pages_processed += 1
          users_processed += 1 unless user_page.continuation_token.present?
          break if user_page.continuation_token.present?
        end
      end

      flush_output_block!(status: status, context: context, buffer: buffer, storage_client: storage_client)
      prepare_reenqueue!(status)
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus).void }
    def self.started!(status)
      context = status_context(status)
      now = Time.now.utc.iso8601
      context[:started_at] = now if context[:started_at].blank?
      context[:heartbeat_at] = now
      status.context = context
      status.started!
      instrument("started", status)
    end

    sig do
      params(
        status: Copilot::MemoryAdminExportJobStatus,
        storage_client: Copilot::MemoryAdminExport::Storage,
      ).void
    end
    def self.completed!(status, storage_client: storage)
      context = status_context(status)
      metadata = metadata_contents(status)
      storage_client.stage_block!(
        filename: context_string(status, :storage_filename),
        block_id: block_id_for(METADATA_BLOCK_INDEX),
        contents: metadata,
      )
      context[:bytes_written] = context_integer_value(context, :bytes_written) + metadata.bytesize
      context[:completed_at] = Time.now.utc.iso8601
      status.context = context
      storage_client.commit_blocks!(
        filename: context_string(status, :storage_filename),
        block_ids: block_ids_for(context_integer_value(context, :part_count)),
      )
      status.success!
      instrument("completed", status)
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus, error: Exception, report: T::Boolean).void }
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
      )
        .returns(StatusContext)
    end
    def self.context_for(owner:, actor:, target_user: nil)
      requested_at = Time.now.utc
      owner_label = label_for(owner)
      context = T.let({
        owner_type: owner_type_for(owner),
        owner_id: owner.id,
        owner_label: owner_label,
        actor_id: actor.id,
        actor_login: actor.display_login,
        requested_at: requested_at.iso8601,
        consistency_cutoff: requested_at.iso8601,
        storage_filename: storage_filename(owner: owner, requested_at: requested_at, target_user: target_user),
        human_filename: human_filename_for(
          owner_label: owner_label,
          requested_at: requested_at,
          target_user_login: target_user&.display_login,
        ),
      }, StatusContext)
      if target_user
        context[:target_user_id] = target_user.id
        context[:target_user_login] = target_user.display_login
      end
      context
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(String) }
    def self.download_url(status)
      storage.download_url(
        filename: context_string(status, :storage_filename),
        expires_in: DOWNLOAD_URL_TTL,
        content_type: CONTENT_TYPE,
        content_disposition: "attachment; filename=\"#{human_filename(status)}\"",
        cache_control: "no-store",
      )
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T::Boolean) }
    def self.blob_exists?(status)
      storage.exists?(context_string(status, :storage_filename))
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus, actor: ::User).returns(T::Boolean) }
    def self.requested_by?(status, actor:)
      context_string(status, :actor_id).to_i == actor.id
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus, actor: ::User).void }
    def self.downloaded!(status, actor:)
      instrument("downloaded", status, actor: actor)
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus).void }
    def self.download_missing_blob!(status)
      failed!(
        status,
        error: MissingBlobError.new("Copilot Memory admin export blob is missing"),
        report: false,
      )
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus, error: Exception).void }
    def self.download_failed!(status, error:)
      Failbot.report(error, log_context(status))
      instrument("download_failed", status, result: "error")
    end

    sig { returns(Copilot::MemoryAdminExport::Storage) }
    def self.storage
      Copilot::MemoryAdminExport::Storage.new
    end

    sig { returns(String) }
    def self.storage_prefix
      "#{GitHub.filename_prefix_for_env}/#{STORAGE_PREFIX}/"
    end

    sig do
      params(
        retention: ActiveSupport::Duration,
        delete_limit: Integer,
        list_page_size: Integer,
        storage_client: Copilot::MemoryAdminExport::Storage,
      ).returns(T::Hash[Symbol, Integer])
    end
    def self.cleanup_expired_blobs(
      retention: BLOB_RETENTION,
      delete_limit: BLOB_CLEANUP_DELETE_LIMIT,
      list_page_size: BLOB_CLEANUP_LIST_PAGE_SIZE,
      storage_client: storage
    )
      raise ArgumentError, "delete_limit must be positive" unless delete_limit.positive?
      raise ArgumentError, "list_page_size must be positive" unless list_page_size.positive?

      prefix = storage_prefix
      ensure_safe_storage_prefix!(prefix)

      cutoff = retention.ago.utc
      marker = T.let(nil, T.nilable(String))
      listed = T.let(0, Integer)
      eligible = T.let(0, Integer)
      deleted = T.let(0, Integer)
      skipped = T.let(0, Integer)
      pages = T.let(0, Integer)

      loop do
        page = storage_client.list_blobs(prefix: prefix, marker: marker, max_results: list_page_size)
        pages += 1

        page.blob_descriptors.each do |blob_descriptor|
          listed += 1
          last_modified = blob_descriptor.last_modified
          next unless last_modified && last_modified < cutoff

          eligible += 1
          if deleted >= delete_limit
            skipped += 1
            next
          end

          deleted += 1 if storage_client.delete_blob(blob_descriptor.name)
        end

        marker = page.continuation_token
        break if marker.blank? || deleted >= delete_limit
      end

      {
        listed: listed,
        eligible: eligible,
        deleted: deleted,
        skipped: skipped,
        pages: pages,
      }
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(String) }
    def self.human_filename(status)
      context_string(status, :human_filename)
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(String) }
    def self.requested_at(status)
      context_string(status, :requested_at)
    end

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T.nilable(String)) }
    def self.requested_at_httpdate(status)
      stored_requested_at = requested_at(status)
      return if stored_requested_at.empty?

      Time.iso8601(stored_requested_at).httpdate
    rescue ArgumentError
      nil
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

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        requested_at: Time,
        target_user: T.nilable(::User),
      ).returns(String)
    end
    def self.storage_filename(owner:, requested_at:, target_user: nil)
      owner_type = owner_type_for(owner).underscore
      user_scope = target_user ? "/user-#{target_user.id}" : ""
      run_id = SecureRandom.uuid
      "#{storage_prefix}#{owner_type}-#{owner.id}#{user_scope}/#{requested_at.to_i}-#{run_id}.#{FORMAT}"
    end

    sig do
      params(
        owner_label: String,
        requested_at: Time,
        target_user_login: T.nilable(String),
      ).returns(String)
    end
    def self.human_filename_for(owner_label:, requested_at:, target_user_login: nil)
      safe_label = owner_label.gsub(/[^A-Za-z0-9._-]+/, "-").downcase
      safe_target = target_user_login&.gsub(/[^A-Za-z0-9._-]+/, "-")&.downcase
      scope = safe_target.present? ? "#{safe_label}-#{safe_target}" : safe_label
      "copilot-memory-user-memories-#{scope}-#{requested_at.to_i}.#{FORMAT}"
    end

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
        status: Copilot::MemoryAdminExportJobStatus,
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
      ).returns(MemoryPage)
    end
    def self.fetch_memory_page(owner:, user_id:, context:)
      response = sweagentd_jobs_client.list_user_memories_for_billing_entity(
        list_user_memories_request(
          owner: owner,
          user_id: user_id,
          continuation_token: context_string_value(context, :current_memory_continuation_token).presence,
          limit: MEMORY_PAGE_SIZE,
          snapshot_time: context_string_value(context, :consistency_cutoff),
        ),
      )
      data = T.let(
        response.data,
        T.nilable(Sweagentd::JobsAPI::V1::ListUserMemoriesForBillingEntityResponse),
      )
      unless data
        return MemoryPage.new(records: [], continuation_token: nil) if response.error&.code == :not_found

        raise GitHub::Sweagentd::Client::Jobs::ApiError,
          "Empty data from sweagentd-jobs-service list_user_memories_for_billing_entity"
      end

      MemoryPage.new(
        records: data.memories.map { |memory| memory_record(owner: owner, user_id: user_id, memory: memory) },
        continuation_token: data.continuation_token.presence,
      )
    ensure
      throttle_memory_fetch!
    end
    private_class_method :fetch_memory_page

    sig { returns(GitHub::Sweagentd::Client::Jobs) }
    def self.sweagentd_jobs_client
      GitHub::Sweagentd::Client::Jobs.new
    end
    private_class_method :sweagentd_jobs_client

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        user_id: Integer,
        continuation_token: T.nilable(String),
        limit: Integer,
        snapshot_time: String,
      ).returns(Sweagentd::JobsAPI::V1::ListUserMemoriesForBillingEntityRequest)
    end
    def self.list_user_memories_request(owner:, user_id:, continuation_token:, limit:, snapshot_time:)
      request = Sweagentd::JobsAPI::V1::ListUserMemoriesForBillingEntityRequest.new(
        user_id: user_id,
        limit: limit,
        continuation_token: continuation_token.to_s,
        snapshot_time: protobuf_timestamp(snapshot_time),
      )

      case owner
      when ::Business
        request.enterprise_id = owner.id
      when ::Organization
        request.organization_id = owner.id
      else
        T.absurd(owner)
      end

      request
    end
    private_class_method :list_user_memories_request

    sig { params(timestamp: String).returns(Google::Protobuf::Timestamp) }
    def self.protobuf_timestamp(timestamp)
      parsed = Time.iso8601(timestamp)
      Google::Protobuf::Timestamp.new(seconds: parsed.to_i, nanos: parsed.nsec)
    end
    private_class_method :protobuf_timestamp

    sig do
      params(
        owner: T.any(::Business, ::Organization),
        user_id: Integer,
        memory: Sweagentd::JobsAPI::V1::Memory,
      ).returns(MemoryRecord)
    end
    def self.memory_record(owner:, user_id:, memory:)
      billing_entity_ids = billing_entity_ids(owner)
      T.let({
        type: "memory",
        schema_version: SCHEMA_VERSION,
        id: memory.id,
        user_id: user_id,
        subject: memory.subject,
        fact: memory.fact,
        citations: memory.citations.to_a,
        reason: memory.reason,
        source: memory_source_record(memory.source),
        scope: "user",
        created_at: timestamp_iso8601(memory.created_at),
        updated_at: timestamp_iso8601(memory.updated_at),
        expires_at: nil,
        billing_organization_id: billing_entity_ids.fetch(:billing_organization_id),
        billing_enterprise_id: billing_entity_ids.fetch(:billing_enterprise_id),
      }, MemoryRecord)
    end
    private_class_method :memory_record

    sig { params(source: T.nilable(Sweagentd::JobsAPI::V1::MemorySource)).returns(T.nilable(MemorySourceRecord)) }
    def self.memory_source_record(source)
      return unless source

      T.let({
        interaction_id: source.interaction_id.presence,
        agent: source.agent.presence,
        commit_sha: source.commit_sha.presence,
        base_model: source.base_model.presence,
        user_id: source.user_id.positive? ? source.user_id.to_i : nil,
        user_login: source.user_login.presence,
      }, MemorySourceRecord)
    end
    private_class_method :memory_source_record

    sig { params(timestamp: T.nilable(Google::Protobuf::Timestamp)).returns(T.nilable(String)) }
    def self.timestamp_iso8601(timestamp)
      return unless timestamp
      return if timestamp.seconds.zero? && timestamp.nanos.zero?

      Time.at(timestamp.seconds, timestamp.nanos, :nanosecond).utc.iso8601(9)
    end
    private_class_method :timestamp_iso8601

    sig { void }
    def self.throttle_memory_fetch!
      Kernel.sleep(MEMORY_FETCH_THROTTLE_SECONDS) if MEMORY_FETCH_THROTTLE_SECONDS.positive?
    end
    private_class_method :throttle_memory_fetch!

    sig do
      params(
        status: Copilot::MemoryAdminExportJobStatus,
        context: StatusContext,
        buffer: String,
        page: MemoryPage,
        user_id: Integer,
        storage_client: Copilot::MemoryAdminExport::Storage,
      ).returns(String)
    end
    def self.append_memory_page!(status:, context:, buffer:, page:, user_id:, storage_client:)
      page_contents = jsonl(page.records)
      if page_contents.present? &&
        buffer.present? &&
        buffer.bytesize + page_contents.bytesize > OUTPUT_BLOCK_TARGET_BYTES
        flush_output_block!(status: status, context: context, buffer: buffer, storage_client: storage_client)
        buffer = +""
      end

      buffer << page_contents
      apply_memory_page_checkpoint!(
        status: status,
        context: context,
        page: page,
        user_id: user_id,
        # Do not checkpoint past buffered records until their block is staged.
        persisted: page_contents.empty? && buffer.empty?,
      )

      if buffer.bytesize >= OUTPUT_BLOCK_TARGET_BYTES
        flush_output_block!(status: status, context: context, buffer: buffer, storage_client: storage_client)
        return +""
      end

      buffer
    end
    private_class_method :append_memory_page!

    sig do
      params(
        status: Copilot::MemoryAdminExportJobStatus,
        context: StatusContext,
        page: MemoryPage,
        user_id: Integer,
        persisted: T::Boolean,
      ).void
    end
    def self.apply_memory_page_checkpoint!(status:, context:, page:, user_id:, persisted:)
      now = Time.now.utc.iso8601
      context[:heartbeat_at] = now
      context[:page_count] = context_integer_value(context, :page_count) + 1
      context[:memory_count] = context_integer_value(context, :memory_count) + page.records.length
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

      return unless persisted

      status.context = context
      status.save
    end
    private_class_method :apply_memory_page_checkpoint!

    sig do
      params(
        status: Copilot::MemoryAdminExportJobStatus,
        context: StatusContext,
        buffer: String,
        storage_client: Copilot::MemoryAdminExport::Storage,
      ).void
    end
    def self.flush_output_block!(status:, context:, buffer:, storage_client:)
      return if buffer.empty?

      part_count = context_integer_value(context, :part_count)
      raise BlockLimitError, "Copilot Memory admin export exceeded Azure block limit" if part_count >= MAX_MEMORY_BLOCKS

      block_index = FIRST_MEMORY_BLOCK_INDEX + part_count
      storage_client.stage_block!(
        filename: context_string_value(context, :storage_filename),
        block_id: block_id_for(block_index),
        contents: buffer,
      )
      context[:part_count] = part_count + 1
      context[:bytes_written] = context_integer_value(context, :bytes_written) + buffer.bytesize
      status.context = context
      status.save
      buffer.clear
    end
    private_class_method :flush_output_block!

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T::Boolean) }
    def self.prepare_reenqueue!(status)
      context = status_context(status)
      reenqueue_count = context_integer_value(context, :reenqueue_count) + 1
      if reenqueue_count > MAX_REENQUEUE_COUNT
        failed!(status, error: ReenqueueLimitError.new("Copilot Memory admin export exceeded re-enqueue limit"))
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
          error: StalledCheckpointError.new("Copilot Memory admin export checkpoint stopped making progress"),
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
        raise MissingBillingEntityError, "Copilot Memory admin export owner has no billing entity"
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

    sig { params(records: T::Array[MemoryRecord]).returns(String) }
    def self.jsonl(records)
      return "" if records.empty?

      records.map { |record| GitHub::JSON.encode(record) }.join("\n") + "\n"
    end
    private_class_method :jsonl

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(String) }
    def self.metadata_contents(status)
      metadata = T.let({
        type: "metadata",
        schema_version: SCHEMA_VERSION,
        owner: context_string(status, :owner_label),
        actor: context_string(status, :actor_login),
        requested_at: context_string(status, :requested_at),
        generated_at: Time.now.utc.iso8601,
        counts: {
          users: context_integer(status, :user_count),
          memories: context_integer(status, :memory_count),
          bytes: context_integer(status, :bytes_written),
          parts: context_integer(status, :part_count),
        },
      }, T::Hash[Symbol, MetadataValue])
      target_user_id = context_optional_integer_value(status_context(status), :target_user_id)
      if target_user_id
        metadata[:target_user_id] = target_user_id
        metadata[:target_user_login] = context_string(status, :target_user_login)
      end

      GitHub::JSON.encode(metadata) + "\n"
    end
    private_class_method :metadata_contents

    sig { params(part_count: Integer).returns(T::Array[String]) }
    def self.block_ids_for(part_count)
      (METADATA_BLOCK_INDEX..part_count).map { |index| block_id_for(index) }
    end
    private_class_method :block_ids_for

    sig { params(index: Integer).returns(String) }
    def self.block_id_for(index)
      if index.negative? || index > MAX_MEMORY_BLOCKS
        raise BlockLimitError, "Copilot Memory admin export block index is invalid"
      end

      Base64.strict_encode64(index.to_s.rjust(BLOCK_ID_WIDTH, "0"))
    end
    private_class_method :block_id_for

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

    sig { params(prefix: String).void }
    def self.ensure_safe_storage_prefix!(prefix)
      env_prefix = GitHub.filename_prefix_for_env
      unless env_prefix.present? && prefix == "#{env_prefix}/#{STORAGE_PREFIX}/"
        raise ArgumentError, "unsafe Copilot Memory admin export storage prefix"
      end
    end
    private_class_method :ensure_safe_storage_prefix!

    sig { params(context: StatusContext).returns(String) }
    def self.checkpoint_fingerprint(context)
      [
        context_integer_value(context, :seat_cursor),
        context_integer_value(context, :current_user_id),
        context_string_value(context, :current_memory_continuation_token),
        context_integer_value(context, :part_count),
        context_integer_value(context, :page_count),
      ].join(":")
    end
    private_class_method :checkpoint_fingerprint

    sig { params(status: Copilot::MemoryAdminExportJobStatus, key: Symbol).returns(Integer) }
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

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(StatusContext) }
    def self.status_context(status)
      status.context || {}
    end
    private_class_method :status_context

    sig { params(status_id: String).returns(String) }
    def self.lease_key(status_id)
      "copilot-memory-admin-export:lease:#{status_id}"
    end
    private_class_method :lease_key

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T::Boolean) }
    def self.reusable_status?(status)
      status.queued? || status.started? || status.success?
    end
    private_class_method :reusable_status?

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T::Boolean) }
    def self.stale?(status)
      return stale_queued?(status) if status.queued?
      return stale_started?(status) if status.started?

      false
    end
    private_class_method :stale?

    sig { params(status: Copilot::MemoryAdminExportJobStatus).void }
    def self.mark_stale!(status)
      error = if status.queued?
        StaleQueuedExportError.new("Copilot Memory admin export did not start")
      else
        StaleHeartbeatError.new("Copilot Memory admin export heartbeat expired")
      end
      failed!(status, error: error)
    end
    private_class_method :mark_stale!

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T::Boolean) }
    def self.stale_queued?(status)
      requested_at = context_time(status, :requested_at)
      return false unless requested_at

      requested_at < QUEUED_STALE_AFTER.ago
    end
    private_class_method :stale_queued?

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T::Boolean) }
    def self.stale_started?(status)
      heartbeat_at = context_time(status, :heartbeat_at) || context_time(status, :started_at)
      return false unless heartbeat_at

      heartbeat_at < HEARTBEAT_STALE_AFTER.ago
    end
    private_class_method :stale_started?

    sig { params(status: Copilot::MemoryAdminExportJobStatus, key: Symbol).returns(T.nilable(Time)) }
    def self.context_time(status, key)
      stored_at = context_string(status, key)
      return if stored_at.blank?

      Time.iso8601(stored_at)
    rescue ArgumentError
      nil
    end
    private_class_method :context_time

    sig do
      params(
        action: String,
        status: Copilot::MemoryAdminExportJobStatus,
        actor: T.nilable(::User),
        result: T.nilable(String),
      ).void
    end
    def self.instrument(action, status, actor: nil, result: nil)
      result ||= action == "failed" ? "error" : "success"
      payload = log_context(status).merge(
        "gh.copilot_memory_admin_export.action" => action,
        "gh.copilot_memory_admin_export.result" => result,
      )
      if actor
        payload["gh.copilot_memory_admin_export.downloader_actor_id"] = actor.id
        payload["gh.copilot_memory_admin_export.downloader_actor_login"] = actor.display_login
      end
      if result == "error"
        GitHub.logger.error("Copilot memory admin export #{action}", payload)
      else
        GitHub.logger.info("Copilot memory admin export #{action}", payload)
      end
      GitHub.dogstats.increment("copilot.memory_admin_export", tags: [
        "action:#{action}",
        "owner_type:#{context_string(status, :owner_type).underscore}",
        "result:#{result}",
      ])
      instrument_terminal_duration(status, result: result) if action == "completed" || action == "failed"
      instrument_audit_event(action, status, actor: actor) if AUDIT_ACTIONS.include?(action)
    end
    private_class_method :instrument

    sig { params(status: Copilot::MemoryAdminExportJobStatus, result: String).void }
    def self.instrument_terminal_duration(status, result:)
      duration = duration_ms(status)
      return if duration.nil?

      context = status_context(status)
      GitHub.dogstats.distribution("copilot.memory_admin_export.duration_ms", duration, tags: [
        "owner_type:#{context_string_value(context, :owner_type).underscore}",
        "scope:#{context.key?(:target_user_id) ? 'user' : 'all'}",
        "result:#{result}",
      ])
    end
    private_class_method :instrument_terminal_duration

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(T.nilable(Float)) }
    def self.duration_ms(status)
      requested_at = context_time(status, :requested_at)
      completed_at = context_time(status, :completed_at)
      return if requested_at.nil? || completed_at.nil?

      GitHub::Dogstats.duration(requested_at, completed_at)
    end
    private_class_method :duration_ms

    sig do
      params(
        action: String,
        status: Copilot::MemoryAdminExportJobStatus,
        actor: T.nilable(::User),
      ).void
    end
    def self.instrument_audit_event(action, status, actor: nil)
      GitHub.instrument(audit_action(status, action: action), audit_payload(status, actor: actor))
    end
    private_class_method :instrument_audit_event

    sig { params(status: Copilot::MemoryAdminExportJobStatus, action: String).returns(String) }
    def self.audit_action(status, action:)
      prefix = case context_string(status, :owner_type)
      when BUSINESS_OWNER_TYPE
        "business"
      when ORGANIZATION_OWNER_TYPE
        "org"
      else
        raise ArgumentError, "unknown Copilot Memory export owner type: #{context_string(status, :owner_type)}"
      end

      "#{prefix}.copilot_memory_admin_export_#{action}"
    end
    private_class_method :audit_action

    sig do
      params(
        status: Copilot::MemoryAdminExportJobStatus,
        actor: T.nilable(::User),
      ).returns(T::Hash[Symbol, T.any(Integer, String)])
    end
    def self.audit_payload(status, actor: nil)
      payload = T.let({
        actor: actor&.display_login || context_string(status, :actor_login),
        actor_id: actor&.id || context_string(status, :actor_id).to_i,
        copilot_memory_export_id: status.id,
        copilot_memory_export_scope: AUDIT_SCOPE,
        copilot_memory_export_format: FORMAT,
        copilot_memory_export_user_count: context_integer(status, :user_count),
        copilot_memory_export_memory_count: context_integer(status, :memory_count),
        copilot_memory_export_page_count: context_integer(status, :page_count),
        requested_at: context_string(status, :requested_at),
      }, T::Hash[Symbol, T.any(Integer, String)])

      completed_at = context_string(status, :completed_at)
      payload[:completed_at] = completed_at if completed_at.present?

      target_user_login = context_string(status, :target_user_login)
      target_user_id = context_string(status, :target_user_id).to_i
      if target_user_login.present? && target_user_id.positive?
        payload[:target_user] = target_user_login
        payload[:target_user_id] = target_user_id
      end

      case context_string(status, :owner_type)
      when BUSINESS_OWNER_TYPE
        payload[:business] = context_string(status, :owner_label)
        payload[:business_id] = context_string(status, :owner_id).to_i
      when ORGANIZATION_OWNER_TYPE
        payload[:org] = context_string(status, :owner_label)
        payload[:org_id] = context_string(status, :owner_id).to_i
      else
        raise ArgumentError, "unknown Copilot Memory export owner type: #{context_string(status, :owner_type)}"
      end

      payload
    end
    private_class_method :audit_payload

    sig { params(status: Copilot::MemoryAdminExportJobStatus).returns(LogContext) }
    def self.log_context(status)
      context = {
        "gh.copilot_memory_admin_export.owner_type" => context_string(status, :owner_type).underscore,
        "gh.copilot_memory_admin_export.owner_id" => context_string(status, :owner_id),
        "gh.copilot_memory_admin_export.actor_id" => context_string(status, :actor_id),
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

    sig { params(status: Copilot::MemoryAdminExportJobStatus, key: Symbol).returns(String) }
    def self.context_string(status, key)
      value = status.context&.fetch(key, nil)
      value.to_s
    end
    private_class_method :context_string
  end
end
