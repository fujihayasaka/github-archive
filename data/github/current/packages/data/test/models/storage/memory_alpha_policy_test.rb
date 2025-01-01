# typed: true
# frozen_string_literal: true

require "test_helper"

class MemoryAlphaPolicyTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @owner = create :user, login: "jessicard", password: GitHub.default_password, plan: "large"
  end

  setup do
    GitHub.s3_uploads_enabled = nil
    GitHub.storage_cluster_enabled = nil
    GitHub.stubs(:s3_production_data_access_key).returns("s3_production_data_access_key")

    @repo = create :repository
    @uploadables = {
      "ReleaseAsset": {
        uploadable: Releases::Public.storage_interface.new(name: "super_release_2021", uploader: @owner, repository: @repo),
        host_match: lambda { |uploadable| uploadable.memory_alpha_fastly_acceleration_bucket(@owner, @repo) },
      },
      "RepositoryFile": {
        uploadable: RepositoryFile.new(name: "repository_file_test", uploader: @owner, repository: @repo),
        host_match: lambda { |uploadable| uploadable.memory_alpha_fastly_acceleration_bucket(@owner, @repo) },
      }
    }

    @proxima_uploadable = Releases::Public.storage_interface.new(name: "flowers_bought_by_clarissa_dalloway", uploader: @owner, repository: @repo)
  end

  teardown do
    Storage::Policy.faraday = nil
  end

  context "S3Sign" do
    test "download_url" do
      @uploadables.each do |key, u|
        GitHub.stubs(:multi_tenant_enterprise?).returns(false)
        p = u[:uploadable].storage_policy(actor: @owner, repository: @repo)
        host_match = u[:host_match].call(u[:uploadable])

        assert_match host_match, p.download_url, key
      end
    end

    test "metadata_url" do
      @uploadables.each do |key, u|
        GitHub.stubs(:multi_tenant_enterprise?).returns(false)
        p = u[:uploadable].storage_policy(actor: @owner, repository: @repo)
        host_match = u[:host_match].call(u[:uploadable])

        assert_match host_match, p.metadata_url, key
      end
    end

    test "upload_url with port" do
      @uploadables.each do |key, u|
        with_env("MEMORY_ALPHA_URL" => "http://github.localhost:8080") do
          p = u[:uploadable].storage_policy(actor: @owner, repository: @repo)
          assert_match "github.localhost:8080", p.upload_url, key
        end
      end
    end

    test "upload_url without port" do
      @uploadables.each do |key, u|
        with_env("MEMORY_ALPHA_URL" => "http://github.localhost") do
          p = u[:uploadable].storage_policy(actor: @owner, repository: @repo)
          assert_match "github.localhost", p.upload_url, key
        end
      end
    end
  end

  context "S3Sign in Proxima" do
    test "download_url" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      p = @proxima_uploadable.storage_policy(actor: @owner, repository: @repo)

      assert_match GitHub.memory_alpha_url, p.download_url, "ReleaseAsset"
    end

    test "metadata_url" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(true)
      p = @proxima_uploadable.storage_policy(actor: @owner, repository: @repo)

      assert_match GitHub.memory_alpha_url, p.metadata_url, "ReleaseAsset"
    end
  end
end
