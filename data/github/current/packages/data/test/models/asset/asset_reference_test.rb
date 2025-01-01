# typed: true
# frozen_string_literal: true

require "test_helper"

class NewAssetReferenceTest < GitHub::TestCase
  fixtures do
    @asset = create(:asset)
    @uploadable = create :media_blob, asset: @asset
  end

  test "validates asset presence" do
    asset_reference = Asset::Reference.new asset: nil, uploadable: @uploadable
    assert_equal false, asset_reference.valid?
    refute_equal [], asset_reference.errors["asset_id"]
  end

  test "validates uploadable presence" do
    asset_reference = Asset::Reference.new asset: @asset
    assert_equal false, asset_reference.valid?
    refute_equal [], asset_reference.errors["uploadable_id"]
    refute_equal [], asset_reference.errors["uploadable_type"]
  end
end
