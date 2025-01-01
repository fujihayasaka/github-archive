# typed: strict
# frozen_string_literal: true

module Copilot
  class JobStatus < ::JobStatus
    include ::JobStatus::Context

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      false
    end

    sig { returns(GitHub::Config::DualWriteKV) }
    def self.kv_store
      Copilot::KV.store
    end
  end
end
