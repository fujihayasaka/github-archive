# typed: true
# frozen_string_literal: true

require "test_helper"

class MemoryAlphaWithDirectAbsDownloadPolicyTest < GitHub::TestCase
  include UploadableTestHelpers

  class FooUploadableType
    def storage_download_expiration
      5.minutes
    end

    def self.abs_storage_account_name
      "foo"
    end

    def abs_storage_account_name
      self.class.abs_storage_account_name
    end
  end

  class BarUploadableType
    def storage_download_expiration
      5.minutes
    end

    def self.abs_storage_account_name
      "bar"
    end

    def abs_storage_account_name
      self.class.abs_storage_account_name
    end
  end

  def build_udk(signed_expiry)
    Azure::Storage::Common::Service::UserDelegationKey.new.tap do |key|
      key.signed_expiry = signed_expiry
      key.signed_oid = "oid"
      key.signed_service = "service"
      key.signed_start = Time.now.utc
      key.signed_tid = "tid"
      key.signed_version = "1.0"
      key.value = "key"
    end
  end

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :repository_test_simple
  end

  setup do

    GitHub.s3_uploads_enabled = nil
    GitHub.storage_cluster_enabled = nil
    GitHub.stubs(:s3_production_data_access_key).returns("s3_production_data_access_key")

    @mock_key = Azure::Storage::Common::Service::UserDelegationKey.new.tap do |key|
      key.signed_expiry = (Time.now.utc + 1.hour).to_s
      key.signed_oid = "oid"
      key.signed_service = "service"
      key.signed_start = Time.now.utc
      key.signed_tid = "tid"
      key.signed_version = "1.0"
      key.value = "key"
    end

    @azure_client = mock("azure client")
    @azure_client.stubs(:get_user_delegation_key).returns(@mock_key)

    @asset = Releases::Public.storage_interface.new(name: "new_release", uploader: @user, repository: @repo)

    disable_feature_flag(Storage::MemoryAlphaWithDirectAbsDownloadPolicy::FEATURE_FLAG_USE_READONLY_SECDONDARY_ENDPOINT)
  end

  teardown do
    Storage::Policy.faraday = nil
  end

  context "download_url" do
    test "without CDN returns ABS URL" do
      Storage::MemoryAlphaWithDirectAbsDownloadPolicy.any_instance.stubs(:blob_client).returns(@azure_client)
      GitHub.stubs(:memory_alpha_fastly_host).returns(nil)
      url = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(@asset).download_url
      assert_includes url, "https://#{GitHub.release_assets_storage_acount}.blob.core.windows.net"
    end

    test "without CDN and secondary endpoint enabled returns ABS SECONDARY URL" do
      Storage::MemoryAlphaWithDirectAbsDownloadPolicy.any_instance.stubs(:blob_client).returns(@azure_client)
      GitHub.stubs(:memory_alpha_fastly_host).returns(nil)
      enable_feature_flag(Storage::MemoryAlphaWithDirectAbsDownloadPolicy::FEATURE_FLAG_USE_READONLY_SECDONDARY_ENDPOINT)
      url = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(@asset).download_url
      assert_includes url, "https://#{GitHub.release_assets_storage_acount}-secondary.blob.core.windows.net"
    end

    test " with CDN returns CDN URL" do
      Storage::MemoryAlphaWithDirectAbsDownloadPolicy.any_instance.stubs(:blob_client).returns(@azure_client)
      asset = Releases::Public.storage_interface.new(name: "new_release", uploader: @user, repository: @repo)
      url = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(@asset).download_url
      assert_includes url, @asset.memory_alpha_fastly_acceleration_bucket(@owner, @repo)
    end

  end

  context "caching" do
    context "blob_client caching" do
      test "reuses same cached blob_client btw same uploadable types" do
        azure_client = mock("azure client")
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_blob_client(FooUploadableType.abs_storage_account_name, azure_client)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal azure_client, policy.send(:blob_client)
        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal azure_client, policy.send(:blob_client)
      end

      test "does not share same cached blob_client for primary and secondary btw same uploadable types" do
        azure_client = mock("azure client")
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_blob_client(FooUploadableType.abs_storage_account_name, azure_client)
        azure_client_secondary = mock("azure client secondary")
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_blob_client("#{FooUploadableType.abs_storage_account_name}-secondary", azure_client_secondary)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal azure_client, policy.send(:blob_client)

        enable_feature_flag(Storage::MemoryAlphaWithDirectAbsDownloadPolicy::FEATURE_FLAG_USE_READONLY_SECDONDARY_ENDPOINT)
        assert_equal azure_client_secondary, policy.send(:blob_client)
      end

      test "does not share cached blob_client btw different uploadable types" do
        azure_client_foo = mock("azure client")
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_blob_client(FooUploadableType.abs_storage_account_name, azure_client_foo)
        azure_client_bar = mock("azure client")
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_blob_client(BarUploadableType.abs_storage_account_name, azure_client_bar)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal azure_client_foo, policy.send(:blob_client)
        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(BarUploadableType.new)
        assert_equal azure_client_bar, policy.send(:blob_client)
      end
    end

    context "UDK" do
      test "reuses same UDK while not expired" do
        udk = build_udk((Time.now.utc + 1.hour).to_s)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_udk(FooUploadableType.abs_storage_account_name, udk)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal udk, policy.send(:user_delegation_key)
      end

      test "fetches a new UDK if expired" do
        none_expired_udk = build_udk((Time.now.utc + 1.hour).to_s)
        azure_client = mock("azure client")
        azure_client.stubs(:get_user_delegation_key).returns(none_expired_udk)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.any_instance.stubs(:blob_client).returns(azure_client)

        # expiration will happen in 1 minutem and the uploadable type has a 5 minute expiration
        expired_udk = build_udk((Time.now.utc + 1.minute).to_s)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_udk(FooUploadableType.abs_storage_account_name, expired_udk)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal none_expired_udk, policy.send(:user_delegation_key)
      end

      test "fetches a new UDK if expiration parameter provided" do
        new_udk = build_udk((Time.now.utc + 1.hour).to_s)
        azure_client = mock("azure client")
        azure_client.stubs(:get_user_delegation_key).returns(new_udk)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.any_instance.stubs(:blob_client).returns(azure_client)

        current_udk = build_udk((Time.now.utc + 1.hour).to_s)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_udk(FooUploadableType.abs_storage_account_name, current_udk)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal new_udk, policy.send(:user_delegation_key, 1.minute)
      end

      test "reuses same cached UDK btw same uploadable types" do
        udk = build_udk((Time.now.utc + 1.hour).to_s)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_udk(FooUploadableType.abs_storage_account_name, udk)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal udk, policy.send(:user_delegation_key)
        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal udk, policy.send(:user_delegation_key)
      end

      test "does not share cached udk btw different uploadable types" do
        udk_foo = build_udk((Time.now.utc + 1.hour).to_s)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_udk(FooUploadableType.abs_storage_account_name, udk_foo)
        udk_bar = build_udk((Time.now.utc + 1.hour).to_s)
        Storage::MemoryAlphaWithDirectAbsDownloadPolicy.add_udk(BarUploadableType.abs_storage_account_name, udk_bar)

        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(FooUploadableType.new)
        assert_equal udk_foo, policy.send(:user_delegation_key)
        policy = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(BarUploadableType.new)
        assert_equal udk_bar, policy.send(:user_delegation_key)
      end
    end
  end

  context "TokenCredential" do
    test "reuses same token_credential while not expired" do
      token = mock("token")
      token_provider = mock("token provider")
      token_provider.stubs(:get_authentication_header).returns(nil)
      token_provider.stubs(:token).returns(token)
      token_provider.stubs(:token_expires_on).returns(Time.now + 1.hour)

      # First call will always fetch the token
      token_credential = Storage::MemoryAlphaWithDirectAbsDownloadPolicy::TokenCredential.new(token_provider, "foo")
      assert_equal token, token_credential.token

      # Second call will return the cached token
      assert_equal token, token_credential.token
    end

    test "fetches a new token_credential if expired" do
      token = mock("token")
      token_provider = mock("token provider")
      token_provider.stubs(:get_authentication_header).returns(nil)
      token_provider.stubs(:token).returns(token)
      token_provider.stubs(:token_expires_on).returns(Time.now + 1.hour)

      # First call will always fetch the token
      token_credential = Storage::MemoryAlphaWithDirectAbsDownloadPolicy::TokenCredential.new(token_provider, "foo")
      assert_equal token, token_credential.token

      # we manually make the token "almost" expired, but enough to pass the minimum expiration check
      token_credential.stubs(:token_expires_on).returns(Time.now + 10.seconds)

      # stub a new token
      new_token = mock("token")
      token_provider.stubs(:token).returns(new_token)

      # Second call should return a new token
      assert_equal new_token, token_credential.token
    end
  end

  context "JWTAuth" do
    test "adds JWT to URL if URL uses Fastly" do
      Storage::MemoryAlphaWithDirectAbsDownloadPolicy.any_instance.stubs(:blob_client).returns(@azure_client)
      GitHub.stubs(:memory_alpha_fastly_host).returns("cdn_url")
      url = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(@asset).download_url

      assert_match /jwt=/, url
    end

    test "does not add JWT to URL if URL does not use Fastly" do
      Storage::MemoryAlphaWithDirectAbsDownloadPolicy.any_instance.stubs(:blob_client).returns(@azure_client)
      GitHub.stubs(:memory_alpha_fastly_host).returns(nil)
      url = Storage::MemoryAlphaWithDirectAbsDownloadPolicy.new(@asset).download_url

      assert !url.include?("jwt=")
    end
  end
end
