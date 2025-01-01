# typed: true
# frozen_string_literal: true

require "test_helper"

module SecretScanning::Models
  class TokenMetadataTest < GitHub::TestCase
    context "is_custom_pattern" do
      test "true if custom pattern (provider / token type)" do
        token_metadata = TokenMetadata.new(provider: "CUSTOM_PATTERN")
        assert token_metadata.is_custom_pattern?

        token_metadata = TokenMetadata.new(provider: "custom_pattern")
        assert token_metadata.is_custom_pattern?

        token_metadata = TokenMetadata.new(token_type: "cp_1234")
        assert token_metadata.is_custom_pattern?
      end

      test "false if not custom pattern" do
        token_metadata = TokenMetadata.new(provider: "CLOJARS")
        refute token_metadata.is_custom_pattern?

        token_metadata = TokenMetadata.new(token_type: "CLOJARS_DEPLOY_TOKEN")
        refute token_metadata.is_custom_pattern?
      end
    end

    context "from_proto" do
      test "returns model from proto definition" do
        proto = GitHub::Proto::SecretScanning::Types::V1::TokenMetadata.new(
          token_type: "CLOJARS_DEPLOY_TOKEN",
          slug: "clojars_deploy_token",
          label: "Clojars Deploy Token",
          provider: "CLOJARS",
        )

        token_metadata = TokenMetadata.from_proto(proto)

        assert_equal "CLOJARS_DEPLOY_TOKEN", token_metadata.token_type
        assert_equal "clojars_deploy_token", token_metadata.slug
        assert_equal "Clojars Deploy Token", token_metadata.label
        assert_equal "CLOJARS", token_metadata.provider
      end
    end

    context "from_hash" do
      test "string keys" do
        hash = {
          "token_type": "CLOJARS_DEPLOY_TOKEN",
          "slug": "clojars_deploy_token",
          "label": "Clojars Deploy Token",
          "provider": "CLOJARS",
        }

        token_metadata = TokenMetadata.from_hash(hash)
        assert_equal "CLOJARS_DEPLOY_TOKEN", token_metadata.token_type
        assert_equal "clojars_deploy_token", token_metadata.slug
        assert_equal "Clojars Deploy Token", token_metadata.label
        assert_equal "CLOJARS", token_metadata.provider
      end

      test "symbol keys" do
        hash = {
          token_type: "CLOJARS_DEPLOY_TOKEN",
          slug: "clojars_deploy_token",
          label: "Clojars Deploy Token",
          provider: "CLOJARS",
        }

        token_metadata = TokenMetadata.from_hash(hash)
        assert_equal "CLOJARS_DEPLOY_TOKEN", token_metadata.token_type
        assert_equal "clojars_deploy_token", token_metadata.slug
        assert_equal "Clojars Deploy Token", token_metadata.label
        assert_equal "CLOJARS", token_metadata.provider
      end
    end

  end
end
