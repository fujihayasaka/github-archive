# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class UploadableTest < Api::SerializerTestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @creator = ::Storage.policy_creator.for(:releases)
    @owner   = create :user
    @repo    = create :repository, owner: @owner, from_example: :repository_test_simple


    @release = create :release, repository: @repo, tag_name: "v1",
      author: @owner, state: :published, created_at: 1.month.ago,
      body: "*version 1*"
  end

  context "#policy_hash" do

    test "cluster payload has expected values" do
      GitHub.storage_cluster_enabled = true

      output = cluster_policy_hash(repository_id: @repo.id, release_id: @release.id)

      assert_equal asset_data[:size], output["form"]["size"]
      assert_equal asset_data[:name], output["form"]["name"]
      assert_equal asset_data[:content_type], output["form"]["content_type"]
      assert_equal "#{GitHub.storage_cluster_url}/releases/#{@release.id}/files", output["upload_url"]
    end

    test "s3 payload has expected values" do
      GitHub.s3_uploads_enabled = true

      output = s3_policy_hash(repository_id: @repo.id, release_id: @release.id)

      assert_equal asset_data[:content_type], output["form"]["Content-Type"]
      assert_equal GitHub.memory_alpha_url + "/github-test-release-asset-2e65be", output["upload_url"]

      assert_match /[0-9a-f]+\/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/, output["form"]["key"]
      assert_equal "private", output["form"]["acl"]
      assert_match %r{/upload/releases/\d+}, output["asset_upload_url"]
    end
  end

  def s3_policy_hash(data)
    data = to_string_keys(asset_data.merge(data))
    uploadable = @creator.create(@owner, data)
    to_string_keys(Api::Serializer.serialize(:policy_hash, uploadable.storage_policy(actor: @owner)))
  end

  def cluster_policy_hash(data)
    uploadable = ReleaseAsset.storage_new(@owner, @blob, asset_data.merge(data))
    to_string_keys(Api::Serializer.serialize(:policy_hash, uploadable.storage_policy(actor: @owner)))
  end

  def to_string_keys(data)
    data.map do |k, v|
      case v
      when Hash
        [k.to_s, to_string_keys(v)]
      else
        [k.to_s, v]
      end
    end.to_h
  end

  def asset_data
    { size: 10, content_type: "application/octet-stream", name: "blob.bin" }
  end
end
