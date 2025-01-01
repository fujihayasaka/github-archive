# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetArchiveTest < GitHub::TestCase
  fixtures do
    @asset = create(:asset)
    @repository = create(:repository)
    @user = @repository.owner
  end

  test "reference and dereference uploadables" do
    assert_same_elements [], @asset.references.reload

    # asset references this avatar
    avatar = create :avatar, asset: @asset, owner: @repository.owner
    @asset.reference! avatar
    assert_same_elements [avatar], @asset.references.reload.map(&:uploadable)

    # asset also references this media blob
    media_blob = create :media_blob, asset: @asset, repository_network: @repository.network
    @asset.reference! media_blob
    assert_same_elements [avatar, media_blob], @asset.references.reload.map(&:uploadable)

    # delete avatar, still references media blob
    avatar.destroy
    archive1 = Asset::Archive.last
    assert_same_elements [media_blob, archive1], @asset.references.reload.map(&:uploadable)
    assert_equal avatar.alambic_path_prefix, T.must(archive1).path_prefix

    # delete media blob, now archive the asset
    media_blob.destroy
    archive2 = Asset::Archive.last
    assert_same_elements [archive1, archive2], @asset.references.reload.map(&:uploadable)
    assert_equal media_blob.alambic_path_prefix, T.must(archive2).path_prefix

    # create avatar, which removes avatar asset::archive, but leaves the blob's
    avatar2 = create :avatar, asset: @asset, owner: @repository.owner
    @asset.reference! avatar2
    assert_same_elements [archive2, avatar2], @asset.references.reload.map(&:uploadable)
    refute Asset::Archive.exists?(T.must(archive1).id)
  end

  test "reference and dereference avatars" do
    user2 = create(:user)

    assert_same_elements [], @asset.references.reload

    avatar1 = create :avatar, asset: @asset, owner: @user
    @asset.reference! avatar1
    assert_same_elements [avatar1], @asset.references.reload.map(&:uploadable)

    avatar2 = create :avatar, asset: @asset, owner: user2
    @asset.reference! avatar2
    assert_same_elements [avatar1, avatar2], @asset.references.reload.map(&:uploadable)

    avatar1.destroy
    assert_same_elements [avatar2], @asset.references.reload.map(&:uploadable)

    # deleting last avatar creates an asset::archive
    avatar2.destroy

    archive1 = Asset::Archive.last
    assert_same_elements [archive1], @asset.references.reload.map(&:uploadable)
    assert_equal avatar2.alambic_path_prefix, T.must(archive1).path_prefix

    # re-creating avatar clears asset::archive

    avatar3 = create :avatar, asset: @asset, owner: @user
    @asset.reference! avatar3
    assert_same_elements [avatar3], @asset.references.reload.map(&:uploadable)
    refute Asset::Archive.exists?(T.must(archive1).id)
  end

  test "reference and dereference media blobs" do
    repository2 = create(:repository)

    media_blob1 = create :media_blob, asset: @asset, repository_network: @repository.network
    @asset.reference! media_blob1
    assert_same_elements [media_blob1], @asset.references.reload.map(&:uploadable)

    media_blob2 = create :media_blob, asset: @asset, repository_network: repository2.network
    @asset.reference! media_blob2
    assert_same_elements [media_blob1, media_blob2], @asset.references.reload.map(&:uploadable)

    media_blob1.destroy
    archive1 = Asset::Archive.last
    assert_same_elements [media_blob2, archive1], @asset.references.reload.map(&:uploadable)
    assert_equal "media/#{@repository.network_id}", T.must(archive1).path_prefix

    media_blob2.destroy
    archive2 = Asset::Archive.last
    assert_same_elements [archive1, archive2], @asset.references.reload.map(&:uploadable)
    assert_equal "media/#{repository2.network_id}", T.must(archive2).path_prefix

    # recreating media blobs remove their specific asset::archive models

    media_blob3 = create :media_blob, asset: @asset, repository_network: repository2.network
    @asset.reference! media_blob3
    assert_same_elements [archive1, media_blob3], @asset.references.reload.map(&:uploadable)

    media_blob4 = create :media_blob, asset: @asset, repository_network: @repository.network
    @asset.reference! media_blob4
    assert_same_elements [media_blob3, media_blob4], @asset.references.reload.map(&:uploadable)
  end

  test "reference archived asset" do
    assert_same_elements [], @asset.references.reload

    # create the media blob, and create an archive record for it
    media_blob = create :media_blob, asset: @asset, repository_network: @repository.network
    @asset.archive! media_blob

    archives = @asset.archives.reload
    assert_equal archives, @asset.references.reload.map(&:uploadable)
    assert_same_elements [media_blob.alambic_path_prefix], archives.map(&:path_prefix)

    # referencing the media blob should clear any asset archive records
    @asset.reference! media_blob
    assert_same_elements [media_blob], @asset.references.reload.map(&:uploadable)
  end

  test "purge multiple IDs" do
    asset1 = create(:asset)
    asset2 = create(:asset)
    asset1.archive! OpenStruct.new(alambic_path_prefix: "test")
    Asset::Archive.update_all(created_at: 1.year.ago)
    asset2.archive! OpenStruct.new(alambic_path_prefix: "test")

    all_archives = Asset::Archive.all
    archive_ids = all_archives.map(&:id)
    assert_same_elements [asset1.id, asset2.id], all_archives.map(&:asset_id).sort

    called = T.let(false, T::Boolean)
    Asset::Archive.stub_purge do |env|
      called = true

      assert_equal :success, Api::Internal.verify_content_hmac(
        # fake rack env
        {
          "REQUEST_METHOD" => env[:method].to_s.upcase,
          "HTTP_CONTENT_HMAC" => env[:request_headers]["Content-HMAC"],
        },
        env[:body],
      )

      body = JSON.parse(env[:body])
      assert_same_elements archive_ids, Array(body["ids"]).sort

      archives = Asset::Archive.all_deleteable(body["ids"])
      assert_same_elements [asset1.id], archives.map(&:asset_id)
      result = archives.map do |archive|
        { path_prefix: archive.path_prefix, oid: archive.asset_oid }
      end

      [200, {}, result.to_json]
    end

    assert Asset::Archive.purge(archive_ids)
    assert called
    assert Asset.exists?(asset2.id)
    assert Asset::Archive.exists?(asset_id: asset2.id)
    refute Asset.exists?(asset1.id)
    refute Asset::Archive.exists?(asset_id: asset1.id)
  end

  test "attempt purge" do
    asset1 = create(:asset)
    asset1.archive! OpenStruct.new(alambic_path_prefix: "test")
    Asset::Archive.update_all(created_at: 1.year.ago)

    called = T.cast(false, T::Boolean)
    Asset::Archive.stub_purge do |_env|
      called = true
      [404, {}, "wat"]
    end

    assert_raises Asset::Archive::PurgeError do
      Asset::Archive.purge(Asset::Archive.all.map(&:id))
    end

    assert called
    assert Asset.exists?(asset1.id)
    assert Asset::Archive.exists?(asset_id: asset1.id)
  end

  teardown do
    Asset::Archive.reset_http!
  end
end
