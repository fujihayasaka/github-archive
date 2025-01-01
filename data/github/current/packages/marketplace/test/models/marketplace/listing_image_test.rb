# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceListingImageTest < GitHub::TestCase
  include UploadableTestHelpers
  include CdnTestHelper

  fixtures do
    @listing = create(:marketplace_listing)
    @user = @listing.listable.user
    @image = Marketplace::ListingImage.new(listing: @listing, uploader: @user)
    save_file_for_uploadable @image, name: "fancy-upload-of-mine.jpg"
  end

  teardown do
    GitHub.marketplace_images_cdn_url = nil
  end

  context "validations" do
    test "allows content types" do
      ctypes = Marketplace::ListingImage.allowed_content_types
      assert_includes ctypes, "image/gif"
      assert_includes ctypes, "image/png"
      assert_includes ctypes, "image/jpeg"
    end

    test "requires a marketplace listing" do
      image = Marketplace::ListingImage.new(marketplace_listing_id: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:listing], :present?
    end

    test "requires an uploader" do
      image = Marketplace::ListingImage.new(uploader_id: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:uploader], :present?
    end

    test "requires a content type" do
      image = Marketplace::ListingImage.new(content_type: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:content_type], :present?
    end

    test "requires a size" do
      image = Marketplace::ListingImage.new(size: nil)
      refute_predicate image, :valid?
      assert_predicate image.errors[:size], :present?
    end

    if GitHub.storage_cluster_enabled?
      test "requires a storage blob" do
        image = Marketplace::ListingImage.new(storage_blob_id: nil)
        refute_predicate image, :valid?
        assert_predicate image.errors[:storage_blob], :present?
      end
    end

    test "requires uploader have permission for integration listing" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      image = build(:marketplace_listing_image, uploader: @user, listing: listing)
      refute_predicate image, :valid?
      assert_predicate image.errors[:uploader], :present?

      image.uploader = integration.owner.admin
      assert_predicate image, :valid?
    end

    test "requires uploader have permission for OAuth app listing" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)
      image = build(:marketplace_listing_image, uploader: @user, listing: listing)
      refute_predicate image, :valid?
      assert_predicate image.errors[:uploader], :present?

      image.uploader = app.user
      assert_predicate image, :valid?
    end
  end

  context "initialization" do
    test "pulls content type from upload" do
      assert_equal "image/jpeg", @image.content_type
    end

    test "pulls size from upload" do
      assert_equal 1.kilobyte, @image.size
    end

    test "pulls filename from upload" do
      assert_equal "fancy-upload-of-mine.jpg", @image.name
    end

    test "sets raw asset uuid" do
      assert_equal @image, Marketplace::ListingImage.find_by(guid: @image.guid)
    end

    test "starts in the starter state" do
      assert Marketplace::ListingImage.new.starter?
    end

    test "sets state on upload" do
      assert @image.uploaded?
    end
  end

  context "storage policy" do
    test "uses cdn url if provided" do
      assert_nil GitHub.marketplace_images_cdn_url

      dl_url = @image.storage_policy.download_url
      assert_equal dl_url, @image.storage_external_url

      GitHub.marketplace_images_cdn_url = "https://ml-images.com/"
      assert_equal "https://ml-images.com/#{@listing.id}/#{@image.guid}", @image.storage_external_url
    end

    test "delete s3 object without cdn" do
      assert_nil GitHub.marketplace_images_cdn_url

      file = create :marketplace_listing_image
      path = "/#{file.marketplace_listing_id}/#{file.guid}"
      assert_storage_policy_delete(file, path) do
        assert_enqueued_jobs(0, only: [PurgeFastlyUrlJob]) do
          file.destroy
        end
      end
    end

    test "delete s3 object with cdn" do
      GitHub.marketplace_images_cdn_url = "https://ml-images.com/"

      file = create :marketplace_listing_image
      path = "/#{file.marketplace_listing_id}/#{file.guid}"
      assert_storage_policy_delete(file, path) do
        assert_purge_url file.storage_external_url do
          file.destroy
        end
      end
    end
  end
end
