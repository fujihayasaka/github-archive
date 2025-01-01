# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Copilot
      # TODO: Reenable this once Sorbet in the Config is fixed:
      # https://github.com/github/app-partitioning/issues/84

      # sig { params(key: T.nilable(String)).returns(T.nilable(String)) }
      def copilot_cdn_hmac_key=(key = nil)
        @copilot_cdn_hmac_key = T.let(key, T.nilable(String))
      end

      # sig { returns(String) }
      def copilot_cdn_hmac_key
        @copilot_cdn_hmac_key ||= ENV["COPILOT_CDN_HMAC_KEY"].to_s
      end

      def api_copilot_hmac_keys
        @api_copilot_hmac_key ||= Kernel.Array(ENV["COPILOT_WORKSPACE_HMAC_KEY"].to_s)
      end

      # sig { returns(T::Boolean) }
      def copilot_enabled?
        !GitHub.enterprise? && GitHub.copilot_cdn_hmac_key.present?
      end

      # sig { returns(T::Boolean) }
      def copilot_for_business_enabled?
        copilot_enabled?
      end

      # sig { returns(T::Boolean) }
      def copilot_for_individuals_enabled?
        copilot_enabled? && !GitHub.multi_tenant_enterprise?
      end

      # sig { params(stamp: T.nilable(String)).returns(T.nilable(String)) }
      def copilot_stamp=(stamp = nil)
        @copilot_stamp = T.let(stamp, T.nilable(String))
      end

      # sig { returns(T.nilable(String)) }
      def copilot_stamp
        @copilot_stamp ||= T.let(ENV["COPILOT_STAMP"], T.nilable(String))
      end

      def copilot_snippy_url
        return "https://snippy-lab.service.iad.github.net/twirp" if GitHub.review_lab?
        "https://origin-tracker.githubusercontent.com/twirp"
      end

      # sig { returns(T.nilable(String)) }
      def dotcom_capi_simple_box_key
        if FeatureFlag.vexi.enabled?("enable-secondary-dotcom-simplebox-key", default: false)
          @dotcom_capi_simple_box_key ||= T.let(ENV["DOTCOM_CAPI_SIMPLE_BOX_KEY_SECONDARY"], T.nilable(String))
        else
          @dotcom_capi_simple_box_key ||= T.let(ENV["DOTCOM_CAPI_SIMPLE_BOX_KEY"], T.nilable(String))
        end
      end

      # sig { params(key: T.nilable(String)) }
      def dotcom_capi_simple_box_key=(key = nil)
        @dotcom_capi_simple_box_key = T.let(key, T.nilable(String))
      end

      # sig { returns(T.nilable(RbNaCl::SimpleBox)) }
      def dotcom_capi_simple_box
        RbNaCl::SimpleBox.from_secret_key(dotcom_capi_simple_box_key.b) unless dotcom_capi_simple_box_key.nil?
      end

      # sig { params(token: T.nilable(String)).returns(T.nilable(::Copilot::EncryptedToken)) }
      def encrypt_and_encode_capi_token(token)
        return if token.nil?

        Kernel.raise RuntimeError.new("dotcom_capi_simple_box_key not set") if dotcom_capi_simple_box.nil?

        encrypted = dotcom_capi_simple_box.encrypt(token)
        value = Base64.urlsafe_encode64(encrypted)
        ::Copilot::EncryptedToken.from(value)
      end

      # sig { params(encoded: T.nilable(String)).returns(T.nilable(::Copilot::DecryptedToken)) }
      def decode_and_decrypt_capi_token(encoded)
        return if encoded.nil?

        Kernel.raise RuntimeError.new("dotcom_capi_simple_box_key not set") if dotcom_capi_simple_box.nil?

        decoded = Base64.urlsafe_decode64(encoded)
        value = dotcom_capi_simple_box.decrypt(decoded)
        ::Copilot::DecryptedToken.from(value)
      end
    end
  end

  extend Config::Copilot
end
