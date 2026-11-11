# typed: strict
# frozen_string_literal: true

module Copilot
  class MemoryAdminExportJobStatus < Copilot::JobStatus
    Attributes = T.type_alias do
      T::Hash[
        Symbol,
        T.any(
          String,
          Integer,
          ActiveSupport::Duration,
          Copilot::MemoryAdminExport::StatusContext,
        )
      ]
    end
    FindMeta = T.type_alias { T::Hash[Symbol, T::Boolean] }

    PREFIX = T.let("copilot-memory-admin-export", String)
    COMPLETED_JOB_TTL = T.let(1.hour, ActiveSupport::Duration)
    INTERNAL_FIND_META = T.let(:memory_admin_export_internal, Symbol)

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      id.start_with?(PREFIX)
    end

    sig do
      params(attributes: Attributes)
        .returns(T.nilable(Copilot::MemoryAdminExportJobStatus))
    end
    def self.create_once(attributes = {})
      status = new(attributes)
      expires_at = Time.now + status.ttl
      created = ActiveRecord::Base.connected_to(role: :writing) do
        kv_store.setnx(send(:cache_key, status.id), status.to_json, expires: expires_at)
      end

      created ? status : nil
    end

    sig do
      params(id: String, meta: FindMeta)
        .returns(T.nilable(Copilot::MemoryAdminExportJobStatus))
    end
    def self.find(id, meta: {})
      return nil unless meta[INTERNAL_FIND_META]

      super(id, meta: meta)
    end

    sig { params(id: String).returns(T.nilable(Copilot::MemoryAdminExportJobStatus)) }
    def self.find_for_export(id)
      find(id, meta: { INTERNAL_FIND_META => true })
    end

    sig { override.params(ttl: ActiveSupport::Duration).void }
    def success!(ttl: COMPLETED_JOB_TTL)
      self.ttl = ttl
      super(ttl: ttl)
    end

    sig { override.params(message: T.nilable(String), ttl: ActiveSupport::Duration).void }
    def error!(message = nil, ttl: COMPLETED_JOB_TTL)
      self.ttl = ttl
      super(message, ttl: ttl)
    end
  end
end
