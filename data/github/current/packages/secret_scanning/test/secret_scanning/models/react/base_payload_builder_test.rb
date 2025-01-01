# typed: true
# frozen_string_literal: true

require "test_helper"

class BasePayloadBuilderTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)

    @repo_async_on_demand_checks_ff = create(:repository, owner: @org)
    GitHub.flipper.enable(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ON_DEMAND_CHECKS_ENABLED_FOR_ASYNC_TOKEN_TYPES, @repo_async_on_demand_checks_ff)

    @payload_builder = SecretScanning::Models::React::BasePayloadBuilder.new(@repo, @user).freeze
    @payload_builder_async_on_demand_checks_ff = SecretScanning::Models::React::BasePayloadBuilder.new(@repo_async_on_demand_checks_ff, @user).freeze
  end

  context "base react payload" do
    async_types = %w[
      NUGET_API_KEY
      MICROSOFT_AZURE_APP_CONFIGURATION_CONNECTION_STRING
      MICROSOFT_AZURE_COMMUNICATION_SERVICES_CONNECTION_STRING
      MICROSOFT_AZURE_IOT_DEVICE_CONNECTION_STRING
      MICROSOFT_AZURE_IOT_HUB_CONNECTION_STRING
      MICROSOFT_AZURE_IOT_PROVISIONING_CONNECTION_STRING
    ]

    test "on-demand checks for async token type supported when ff is disabled" do
      async_types.each do |token_type|
        req_at = nil
        case token_type
        when "NUGET_API_KEY"
          req_at = Time.now
        when "MICROSOFT_AZURE_IOT_DEVICE_CONNECTION_STRING"
          req_at = Time.now - (3 * 60)
        when "MICROSOFT_AZURE_IOT_PROVISIONING_CONNECTION_STRING"
          req_at = Time.now - (7 * 60)
        end
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "#{token_type} label",
          token_type: token_type,
          repository_id: @repo.id,
          number: 1,
          validity: :TOKEN_VALIDITY_ACTIVE,
          # TSS will not include a last checked date in validation details for this token type, because a token used in a tuple
          # won't have a last checked. It would be part of a group, and that would would have a last checked.
          validation_details: {
            async_check_requested_at: req_at
          },
          # validation_support.validity_checks_supported determines whether to show that a token was not yet checked if it does
          # not have a last checked date.
          # validation_support.on_demand_checks_supported determines whether to show the on-demand check button for a token type
          # this is not yet supported for AWS token types
          validation_support: {
            on_demand_checks_supported: true,
            validity_checks_supported: true,
          }
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

        serialized_alert = @payload_builder.serialize_alert(token)

        assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
        refute serialized_alert.validation_support.on_demand_checks_supported
        if !GitHub.single_or_multi_tenant_enterprise?
          assert serialized_alert.validation_support.validity_checks_supported
        else
          refute serialized_alert.validation_support.validity_checks_supported
        end
        assert_nil serialized_alert.validity_last_checked
        case serialized_alert.token_type
        when "NUGET_API_KEY"
          # because req_at = Time.now
          assert serialized_alert.async_check_in_progress
        when "MICROSOFT_AZURE_IOT_DEVICE_CONNECTION_STRING"
          # because req_at = Time.now - (3 * 60)
          assert serialized_alert.async_check_in_progress
        when "MICROSOFT_AZURE_IOT_PROVISIONING_CONNECTION_STRING"
          # because req_at = Time.now - (7 * 60)
          refute serialized_alert.async_check_in_progress
        else
          # because req_at is nil
          refute serialized_alert.async_check_in_progress
        end
      end
    end

    test "on-demand checks for async token type supported when ff is enabled" do
      async_types.each do |token_type|
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "#{token_type} label",
          token_type: token_type,
          repository_id: @repo.id,
          number: 1,
          validity: :TOKEN_VALIDITY_ACTIVE,
          # TSS will not include a last checked date in validation details for this token type, because a token used in a tuple
          # won't have a last checked. It would be part of a group, and that would would have a last checked.
          validation_details: {},
          # validation_support.validity_checks_supported determines whether to show that a token was not yet checked if it does
          # not have a last checked date.
          # validation_support.on_demand_checks_supported determines whether to show the on-demand check button for a token type
          # this is not yet supported for AWS token types
          validation_support: {
            on_demand_checks_supported: true,
            validity_checks_supported: true,
          }
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

        serialized_alert = @payload_builder_async_on_demand_checks_ff.serialize_alert(token)

        assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
        if !GitHub.single_or_multi_tenant_enterprise?
          assert serialized_alert.validation_support.on_demand_checks_supported
          assert serialized_alert.validation_support.validity_checks_supported
        else
          refute serialized_alert.validation_support.on_demand_checks_supported
          refute serialized_alert.validation_support.validity_checks_supported
        end
        assert_nil serialized_alert.validity_last_checked
      end
    end

    test "uses tss validity for aws keys when FF is enabled" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Amazon AWS Secret Access Key",
        token_type: "AWS_SECRET",
        repository_id: @repo.id,
        number: 1,
        validity: :TOKEN_VALIDITY_ACTIVE,
        # TSS will not include a last checked date in validation details for this token type, because a token used in a tuple
        # won't have a last checked. It would be part of a group, and that would would have a last checked.
        validation_details: {},
        # validation_support.validity_checks_supported determines whether to show that a token was not yet checked if it does
        # not have a last checked date.
        # validation_support.on_demand_checks_supported determines whether to show the on-demand check button for a token type
        # this is not yet supported for AWS token types
        validation_support: {
          on_demand_checks_supported: false,
          validity_checks_supported: false,
        }
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
      refute serialized_alert.validation_support.on_demand_checks_supported
      refute serialized_alert.validation_support.validity_checks_supported
      assert_nil serialized_alert.validity_last_checked
    end

    test "aws on-demand validity checks enabled when TSS says they are" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Amazon AWS Secret Access Key",
        token_type: "AWS_SECRET",
        repository_id: @repo.id,
        number: 1,
        validity: :TOKEN_VALIDITY_ACTIVE,
        validation_details: {},
        validation_support: {
          on_demand_checks_supported: true,
          validity_checks_supported: false,
        },
        token_groups: [GitHub::Proto::SecretScanning::Api::V2::TokenGroup.new]
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
      if !GitHub.single_or_multi_tenant_enterprise?
        assert serialized_alert.validation_support.on_demand_checks_supported
      else
        refute serialized_alert.validation_support.on_demand_checks_supported
      end
      refute serialized_alert.validation_support.validity_checks_supported
      assert_nil serialized_alert.validity_last_checked
    end

    test "aws on-demand validity checks not supported when TSS says they are not" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Amazon AWS Secret Access Key",
        token_type: "AWS_SECRET",
        repository_id: @repo.id,
        number: 1,
        validity: :TOKEN_VALIDITY_ACTIVE,
        validation_details: {},
        validation_support: {
          on_demand_checks_supported: false,
          validity_checks_supported: false,
        },
        token_groups: [GitHub::Proto::SecretScanning::Api::V2::TokenGroup.new]
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
      refute serialized_alert.validation_support.on_demand_checks_supported
      refute serialized_alert.validation_support.validity_checks_supported
      assert_nil serialized_alert.validity_last_checked
    end

    test "validity checks and on-demand checks for a github token type are supported when TSS says they are" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_PERSONAL_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
        validity: :TOKEN_VALIDITY_ACTIVE,
        validation_details: {},
        validation_support: {
          on_demand_checks_supported: true,
          validity_checks_supported: true,
        },
        token_groups: [GitHub::Proto::SecretScanning::Api::V2::TokenGroup.new]
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
      assert serialized_alert.validation_support.on_demand_checks_supported
      assert serialized_alert.validation_support.validity_checks_supported
      assert_nil serialized_alert.validity_last_checked
    end

    test "validity checks and on-demand checks for a github token type are not supported when TSS says they are not" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_PERSONAL_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
        validity: :TOKEN_VALIDITY_ACTIVE,
        validation_details: {},
        validation_support: {
          on_demand_checks_supported: false,
          validity_checks_supported: false,
        },
        token_groups: [GitHub::Proto::SecretScanning::Api::V2::TokenGroup.new]
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
      refute serialized_alert.validation_support.on_demand_checks_supported
      refute serialized_alert.validation_support.validity_checks_supported
      assert_nil serialized_alert.validity_last_checked
    end

    test "uses validity from TSS" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
        validity: :TOKEN_VALIDITY_ACTIVE,
        validation_details: {
          validity_last_checked: Time.parse("2022-10-21")
        }
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal :TOKEN_VALIDITY_ACTIVE, serialized_alert.validity
      assert_equal 2022, serialized_alert.validity_last_checked.year
      assert_equal 10, serialized_alert.validity_last_checked.month
      assert_equal 21, serialized_alert.validity_last_checked.day
    end

    test "serialize open alert" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21"), commit_oid: "b5d4f15a4dd41646405f11fb107aa8efb16c98a4")
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: location,
        id: 1,
        label: "Adafruit IO Key",
        token_type: "adafruit_io_key",
        token_type_provider: "Adafruit",
        repository_id: @repo.id,
        number: 1
      )

      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      first_location_description = "Detected secret in app/models/user.rb:12"

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal 1, serialized_alert.number
      assert_equal "Adafruit IO Key", serialized_alert.label
      assert_equal "adafruit_io_key", serialized_alert.token_type
      assert_equal "Adafruit", serialized_alert.token_type_provider
      assert_equal false, serialized_alert.is_closed

      assert_nil serialized_alert.resolved_at
      assert_nil serialized_alert.resolution
    end

    test "serialize closed alert" do
      location = GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21"), commit_oid: "b5d4f15a4dd41646405f11fb107aa8efb16c98a4")
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: location,
        id: 1,
        label: "Adafruit IO Key",
        token_type: "adafruit_io_key",
        token_type_provider: "Adafruit",
        repository_id: @repo.id,
        number: 1,
        resolution: GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED,
        resolved_at: Time.parse("2023-03-23")
      )

      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal true, serialized_alert.is_closed
      refute_nil serialized_alert.resolved_at
      assert_equal "revoked", serialized_alert.resolution
    end
  end

  context "raw secret" do
    test "uses raw secret from encrypted secret when available" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Amazon AWS Secret Access Key",
        token_type: "AWS_SECRET",
        repository_id: @repo.id,
        number: 1,
        encrypted_token: "encrypted_content"
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      SecretScanning::Encryption::EncryptedSecretsCryptoHelper.expects(:decrypt_encrypted_secret).once.returns("decrypted_raw_secret")
      serialized_alert = @payload_builder.serialize_alert(token)

      assert_equal "decrypted_raw_secret", serialized_alert.raw_secret
    end

    test "does not use raw secret from blobs as fallback when disable fetch blobs ff is enabled" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(
          created_at: Time.parse("2022-10-21"),
          path: "path/to/file.rb",
          start_line: 1,
          blob_oid: "123",
        ),
        id: 1,
        label: "Amazon AWS Secret Access Key",
        token_type: "AWS_SECRET",
        repository_id: @repo.id,
        number: 1,
        encrypted_token: nil,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      SecretScanning::Models::React::BasePayloadBuilder.any_instance.expects(:fetch_blobs).never

      @payload_builder.serialize_alert(token)
    end
  end
end
