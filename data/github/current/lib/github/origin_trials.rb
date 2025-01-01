# typed: true
# frozen_string_literal: true
require "json"
require "ed25519"

module GitHub
  module OriginTrials
    extend T::Sig
    extend T::Helpers
    sealed!

    TRIALS = {
      popup_api: "ArUyrlFzYHusLn8hds4mcWW01ATOQA3neyFAI9BRFshwufcq989qQoSsoyM0QBaQLZ+imOkYzfuGqr6+3fvO7w8AAABpeyJvcmlnaW4iOiJodHRwczovL2dpdGh1Yi5jb206NDQzIiwiZmVhdHVyZSI6IkhUTUxQb3B1cEF0dHJpYnV0ZSIsImV4cGlyeSI6MTY4MDY1Mjc5OSwiaXNTdWJkb21haW4iOnRydWV9",
      soft_web_vitals: "AsAplJTn1iZ5xwBnn8KD6B+KlpcWCc8zjB6x2+zYNBV8l4+JkBvck390rU3q06DC26GH3TYVNRN5UioyB+vgYAMAAABceyJvcmlnaW4iOiJodHRwczovL2dpdGh1Yi5jb206NDQzIiwiZmVhdHVyZSI6IlNvZnROYXZpZ2F0aW9uSGV1cmlzdGljcyIsImV4cGlyeSI6MTcwOTY4MzE5OX0="
    }

    # Google Chrome's public key
    # https://github.com/chromium/chromium/blob/main/content/shell/common/shell_origin_trial_policy.cc#L20
    CHROME_KEY = Ed25519::VerifyKey.new("fMS4mpO6buLQ/QMd+zJmxzty/VQ6B1EUZqoCU04zoRU=".unpack("m*").first)

    class Trial < T::Struct
      extend T::Sig
      include FeatureFlagHelper

      prop :feature_flag, Symbol
      prop :token, String

      sig { returns(Time) }
      def expires_at
        @expires_at ||= Time.at(payload["expiry"].to_i)
      end

      sig { returns(String) }
      def feature
        @feature ||= payload["feature"]
      end

      sig { returns(String) }
      def origin
        @origin ||= payload["origin"]
      end

      sig { returns(T::Boolean) }
      def valid?
        begin
          CHROME_KEY.verify(signature, "#{[version].pack("C")}#{[payload_length].pack("I>")}#{payload_str}")
        rescue Ed25519::VerifyError
          false
        end
      end

      sig { returns(T::Boolean) }
      def expired?
        expires_at < Date.today.to_time
      end

      sig { params(user: User).returns(T::Boolean) }
      def active_for_user?(user)
        feature_enabled_globally_or_for_user?(feature_name: feature_flag, subject: user)
      end

      private

      VERSION_BYTE_SIZE = 1
      sig { returns(Integer) }
      def version
        @version ||= T.must(token_bytes.byteslice(0, VERSION_BYTE_SIZE)).ord
      end

      sig { returns(String) }
      def token_bytes
        @token_bytes ||= T.must(token.unpack("m*").first)
      end

      SIGNATURE_BYTE_SIZE = 64
      sig { returns(String) }
      def signature
        @signature ||= T.must(token_bytes.byteslice(VERSION_BYTE_SIZE, SIGNATURE_BYTE_SIZE))
      end

      PAYLOAD_LENGTH_BYTE_SIZE = 4
      def payload_length
        @payload_length ||= T.must(token_bytes.byteslice(VERSION_BYTE_SIZE + SIGNATURE_BYTE_SIZE, PAYLOAD_LENGTH_BYTE_SIZE)).unpack("I>").first
      end

      def payload_str
        @payload_str ||= token_bytes.byteslice(VERSION_BYTE_SIZE + SIGNATURE_BYTE_SIZE + PAYLOAD_LENGTH_BYTE_SIZE, payload_length)
      end

      def payload
        @payload ||= JSON.parse(payload_str)
      end

    end

    sig { params(user: User, trials: T::Enumerable[Trial]).returns(T::Enumerable[Trial]) }
    def self.active_trials(user:, trials: GitHub::OriginTrials.global_trials)
      trials.select { |trial| !trial.expired? && trial.active_for_user?(user) }
    end

    sig { params(trials: T::Enumerable[Trial]).returns(T::Enumerable[Trial]) }
    def self.current_trials(trials: GitHub::OriginTrials.global_trials)
      trials.reject(&:expired?)
    end

    sig { returns(T::Enumerable[Trial]) }
    def self.global_trials
      @trials ||= TRIALS.map do |feature_flag, token|
        GitHub::OriginTrials::Trial.new(feature_flag: feature_flag, token: token)
      end
    end
  end
end
