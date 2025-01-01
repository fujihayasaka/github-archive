# typed: true
# frozen_string_literal: true

require "test_helper"

class AssetTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  AlambicPathMock = Struct.new(:alambic_path_prefix)
  fixtures do
    @repo = create(:repository)
    @user = create(:user)

    meta = {
      size: 1,
      content_type: "image/png",
      width: 10,
      height: 10,
      owner_type: "User",
    }

    @av = Avatar.upload(@repo.owner, Sham.sha256, meta.merge(owner_id: @repo.owner.id))
    @asset = @av.asset

    @av2 = Avatar.upload(@repo.owner, Sham.sha256, meta.merge(owner_id: @repo.owner.id))
    @asset2 = @av2.asset
    @av3 = Avatar.upload(@user, @asset2.oid, meta.merge(owner_id: @user.id))

    @fake_uploadable = AlambicPathMock.new(alambic_path_prefix: "test")

    @archived = create(:asset)
    @archived.archive!(@fake_uploadable)
  end

  test "upload cannot initialize asset with different size" do
    assert_raises ActiveRecord::RecordInvalid do
      asset = T.must(Asset.find_by oid: @asset.oid)
      asset.update_meta size: @asset.size + 1
    end
  end

  test "oid is required" do
    asset = build :asset, oid: nil
    assert_equal false, asset.valid?
    refute_equal [], asset.errors["oid"]
  end

  test "oid is 64 characters" do
    asset = build :asset, oid: "abcde"
    assert_equal false, asset.valid?
    refute_equal [], asset.errors["oid"]
  end

  test "oid is unique" do
    asset = build :asset, oid: @asset.oid
    assert_equal false, asset.save
    refute_equal [], asset.errors["oid"]
  end

  test "size is required" do
    asset = build :asset, size: nil
    assert_equal false, asset.valid?
    refute_equal [], asset.errors["size"]
  end

  test "size must be set" do
    asset = build :asset, size: -1
    assert_equal false, asset.valid?
    refute_equal [], asset.errors["size"]
  end

  context "references" do
    test "reference an uploadable on an asset with one reference" do
      assert_same_elements [@av], @asset.references.map(&:uploadable)

      blob = create :media_blob, repository_network: @repo.network, asset: @asset
      @asset.reference! blob
      assert_same_elements [@av, blob], @asset.references.reload.map(&:uploadable)

      @asset.reference! blob
      assert_same_elements [@av, blob], @asset.references.reload.map(&:uploadable)
    end

    test "reference an uploadable on an asset with multiple references" do
      assert_same_elements [@av2, @av3], @asset2.references.map(&:uploadable)

      blob = create :media_blob, repository_network: @repo.network, asset: @asset2
      @asset2.reference! blob
      assert_same_elements [@av2, @av3, blob], @asset2.references.reload.map(&:uploadable)

      @asset2.reference! blob
      assert_same_elements [@av2, @av3, blob], @asset2.references.reload.map(&:uploadable)
    end

    test "reference an invalid uploadable" do
      assert_raises GitHub::DataQualityError do
        @asset.reference! nil
      end
    end

    test "dereference an asset uploadable" do
      assert_same_elements [@av2, @av3], @asset2.references.map(&:uploadable)
      @asset2.dereference! @av3
      assert_same_elements [@av2], @asset2.references.reload.map(&:uploadable)
    end

    test "dereference an asset's last uploadable" do
      assert_same_elements [@av], @asset.references.map(&:uploadable)
      @asset.dereference! @av
      archive = Asset::Archive.last
      assert_same_elements [archive], @asset.references.reload.map(&:uploadable)
    end

    test "dereference an invalid uploadable" do
      assert_raises GitHub::DataQualityError do
        @asset.dereference! nil
      end
    end

    test "re-archiving asset bumps created_at" do
      Asset::Archive.update_all created_at: Time.local(2000)
      archive = @archived.archives.first
      assert_equal 1, @archived.archives.count
      original_created_at = archive.created_at
      assert_equal 2000, original_created_at.year

      @archived.archive!(@fake_uploadable)
      archive.reload
      assert original_created_at < archive.created_at
      assert_equal Time.now.utc.year, archive.created_at.year
    end

    test "purge with no archives" do
      assert_equal false, @asset.purge!([])
      assert Asset.exists?(@asset.id)
    end

    test "purge with other asset's archive" do
      assert_equal false, @asset.purge!(@archived.archives)
      assert Asset.exists?(@asset.id)
    end

    test "purge with partial archives" do
      asset = create(:asset)
      asset.archive! AlambicPathMock.new(alambic_path_prefix: "test1")
      asset.archive! AlambicPathMock.new(alambic_path_prefix: "test2")
      assert_equal %w(test1 test2), asset.archives.reload.map(&:path_prefix)

      assert_equal false, asset.purge!([asset.archives.first])
      assert_equal %w(test2), asset.archives.reload.map(&:path_prefix)
      assert Asset.exists?(asset.id)
    end

    test "purge with all archives" do
      asset = create(:asset)
      asset.archive! AlambicPathMock.new(alambic_path_prefix: "test1")
      asset.archive! AlambicPathMock.new(alambic_path_prefix: "test2")
      assert_equal %w(test1 test2), asset.archives.map(&:path_prefix)

      assert_equal true, asset.purge!(asset.archives)
      assert_equal [], asset.archives.reload
      refute Asset.exists?(asset.id)
    end
  end
end
