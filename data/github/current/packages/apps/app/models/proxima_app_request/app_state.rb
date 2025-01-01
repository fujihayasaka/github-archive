# typed: strict
# frozen_string_literal: true

# This class models the state of an App on a Proxima Stamp
# It contains the global relay id and the fingerprint of the app
# on the Proxima Stamp
class ProximaAppRequest
  class AppState
    extend T::Sig
    include ProximaAppHelper

    UnknownGlobalRelayId = Class.new(StandardError)

    sig { returns(String) }
    attr_reader :global_relay_id

    sig { returns(String) }
    attr_reader :fingerprint

    sig { params(global_relay_id: String, fingerprint: String).void }
    def initialize(global_relay_id, fingerprint)
      @global_relay_id = global_relay_id
      @fingerprint = fingerprint
      @application = T.let(nil, T.nilable(T.any(OauthApplication, Integration)))
    end

    sig { returns(T::Boolean) }
    def current?
      return true if unavailable?

      fingerprint == T.must(application).synchronization_fingerprint
    end

    sig { returns(T::Boolean) }
    def outdated?
      !current?
    end

    sig { returns(T::Boolean) }
    def available?
      !!application&.syncable_to_proxima?
    end

    sig { returns(T::Boolean) }
    def unavailable?
      !available?
    end

    sig { returns(T::Hash[String, T.any(String, T::Boolean)]) }
    def current_state_hash
      if unavailable?
        {
          "global_relay_id" => global_relay_id,
          "fingerprint" => fingerprint,
          "marked_for_deletion" => true
        }
      else
        {
          "global_relay_id" => global_relay_id,
          "fingerprint" => T.must(application).synchronization_fingerprint
        }
      end
    end

    sig { returns(T.nilable(T.any(OauthApplication, Integration))) }
    def application
      @application ||= app_from_global_id(global_relay_id)
    end
  end
end
