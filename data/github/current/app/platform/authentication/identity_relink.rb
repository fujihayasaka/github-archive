# typed: true
# frozen_string_literal: true

require "securerandom"

module Platform
  module Authentication
    class IdentityRelink
      # Making the new methods private since the class is intended to be accessed through
      # initiate and consume methods only
      private_class_method :new

      DEFAULT_EXPIRY = 65.minutes

      def initialize(persistent_store: nil)
        @persistent_store = persistent_store
      end

      # generate a new session token and return it to be passed along as form
      # data before calling saml/continue
      def self.generate_identity_relink_session_token(session_key:, persistent_store: nil)
        new(persistent_store: persistent_store).generate_identity_relink_session_token(session_key: session_key)
      end

      # verify the session token that has been passed in by querying for a
      # value using the provided key and returning the output with the provided
      # value
      def self.verify_session_token(session_key: , session_token:, persistent_store: nil)
        new(persistent_store: persistent_store).verify_session_token(session_key: session_key, session_token: session_token)
      end

      def generate_identity_relink_session_token(session_key:)
        session_token = SecureRandom.urlsafe_base64(80)

        persistent_store.set(session_key, session_token, expires: DEFAULT_EXPIRY.from_now)

        session_token
      end

      def verify_session_token(session_key: , session_token:)
        persisted_session_token = persistent_store.get(session_key).value { nil }

        return false if persisted_session_token.nil?

        # remove the key to prevent multiple uses
        persistent_store.del(session_key)

        persisted_session_token == session_token
      end

      def persistent_store
        @persistent_store ||= GitHub.kv # rubocop:todo GitHub/DoNotUseGlobalKv
      end
    end
  end
end
