# typed: true
# frozen_string_literal: true

require "json"
require "ed25519"
require "openssl"

module GitHub
  module OriginTrials
    extend T::Helpers
    sealed!

    TRIALS = {
      soft_web_vitals: "AsAplJTn1iZ5xwBnn8KD6B+KlpcWCc8zjB6x2+zYNBV8l4+JkBvck390rU3q06DC26GH3TYVNRN5UioyB+vgYAMAAABceyJvcmlnaW4iOiJodHRwczovL2dpdGh1Yi5jb206NDQzIiwiZmVhdHVyZSI6IlNvZnROYXZpZ2F0aW9uSGV1cmlzdGljcyIsImV4cGlyeSI6MTcwOTY4MzE5OX0=",
      # "AriaNotify API" in Microsoft Edge
      # https://developer.microsoft.com/en-us/microsoft-edge/origin-trials/trials/a05622fb-4cd9-42f4-ac8d-1a2f62de139b
      # Expires on 2025-07-05
      arianotify_partial_migration: "Azy6e/8DtII51WpuhX0dG35PHazFm4cvNCqWtGjwopgxbUSURgNkAQbZTBX+GN4GIXWrxMlbfXOeKOtzCWQVNNUAAABOeyJvcmlnaW4iOiJodHRwczovL2dpdGh1Yi5jb206NDQzIiwiZmVhdHVyZSI6IkFyaWFOb3RpZnkiLCJleHBpcnkiOjE3NTE3Mjg3NTh9",
      arianotify_comprehensive_migration: "Azy6e/8DtII51WpuhX0dG35PHazFm4cvNCqWtGjwopgxbUSURgNkAQbZTBX+GN4GIXWrxMlbfXOeKOtzCWQVNNUAAABOeyJvcmlnaW4iOiJodHRwczovL2dpdGh1Yi5jb206NDQzIiwiZmVhdHVyZSI6IkFyaWFOb3RpZnkiLCJleHBpcnkiOjE3NTE3Mjg3NTh9"
    }

    # Google Chrome's public key (Ed25519, 32 bytes)
    # https://github.com/chromium/chromium/blob/main/components/embedder_support/origin_trials/origin_trial_policy_impl.cc#L27-L32
    CHROME_KEY = Ed25519::VerifyKey.new("fMS4mpO6buLQ/QMd+zJmxzty/VQ6B1EUZqoCU04zoRU=".unpack("m*").first)

    # Microsoft Edge's public key (ES256, 64 bytes)
    # https://microsoft.visualstudio.com/Edge/_git/chromium.src?path=/components/embedder_support/origin_trials/origin_trial_policy_impl.cc&version=GBmain&line=34&lineEnd=42&lineStartColumn=1&lineEndColumn=1&lineStyle=plain&_a=contents
    EDGE_KEY = OpenSSL::PKey::EC.new("prime256v1").tap do |key|
      bytes = "bWyhULXLN4WdPSh58zy0YkihBAXpBGfJket5ans58EJrPJg0CLkSfHwylT3X1+jihwi4kerhqwKeyeGEktu4Dg==".unpack1("m*")
      key.public_key = OpenSSL::PKey::EC::Point.new(key.group, "\x04#{bytes}")
    end

    # How to convert hex bytes to a base64 string in Ruby:
    #
    # require "base64"
    # bytes = [
    #     0x7c, 0xc4, 0xb8, 0x9a, 0x93, 0xba, 0x6e, 0xe2, 0xd0, 0xfd, 0x03,
    #     0x1d, 0xfb, 0x32, 0x66, 0xc7, 0x3b, 0x72, 0xfd, 0x54, 0x3a, 0x07,
    #     0x51, 0x14, 0x66, 0xaa, 0x02, 0x53, 0x4e, 0x33, 0xa1, 0x15
    # ]
    # buf = bytes.pack("C*")
    # puts Base64.strict_encode64(buf)
    #
    # fMS4mpO6buLQ/QMd+zJmxzty/VQ6B1EUZqoCU04zoRU=

    class Trial < T::Struct
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
        valid_for_chrome = begin
          CHROME_KEY.verify(signature, "#{[version].pack("C")}#{[payload_length].pack("I>")}#{payload_str}")
        rescue Ed25519::VerifyError
          false
        end
        valid_for_edge = begin
          EDGE_KEY.dsa_verify_asn1(
            Digest::SHA256.digest("#{[version].pack("C")}#{[payload_length].pack("I>")}#{payload_str}"),
            OpenSSL::ASN1::Sequence([
              OpenSSL::ASN1::Integer(OpenSSL::BN.new(signature[0, 32], 2)),
              OpenSSL::ASN1::Integer(OpenSSL::BN.new(signature[32, 32], 2))
            ]).to_der
          )
        rescue OpenSSL::PKey::ECError, OpenSSL::ASN1::ASN1Error
          false
        end
        valid_for_chrome || valid_for_edge
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
