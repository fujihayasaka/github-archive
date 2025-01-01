# typed: strict
# frozen_string_literal: true

class SignupFlowKV
  extend T::Sig

  sig { returns(GitHub::KV) }
  def self.store
    @store ||= T.let(build_store, T.nilable(GitHub::KV))
  end

  sig { returns(GitHub::KV) }
  def self.build_store
    config = GitHub::KV.config.dup
    config.table_name = :signup_flow_key_values

    GitHub::KV.new(config: config) do
      ::ApplicationRecord::Domain::SignupFlow.connection
    end
  end
end
