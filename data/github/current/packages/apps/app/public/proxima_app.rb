# typed: strict
# frozen_string_literal: true

# This module is a public interface callers outside this package can use to
# synchronize apps with Proxima
module ProximaApp
  extend T::Sig
  extend ProximaAppHelper

  sig { params(app_states: T::Array[T::Hash[String, String]], party_type: T.nilable(String)).returns(ProximaAppRequest) }
  def self.synchronization_from(app_states, party_type)
    party_type ||= "first" # Default to first for now
    ProximaAppRequest.from(app_states, party_type: party_type)
  end
end
