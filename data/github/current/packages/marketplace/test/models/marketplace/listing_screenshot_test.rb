# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceListingScreenshotTest < GitHub::TestCase
  include UploadableTestHelpers
  include CdnTestHelper

  fixtures do
    @listing = create(:marketplace_listing)
    @user = @listing.listable.user
    @screenshot = Marketplace::ListingScreenshot.new(listing: @listing, uploader: @user)
    save_file_for_uploadable @screenshot, name: "fancy-upload-of-mine.jpg"
  end

  teardown do
    GitHub.marketplace_screenshots_cdn_url = nil
  end

  context "validations" do
    test "allows content types" do
      ctypes = Marketplace::ListingScreenshot.allowed_content_types
      assert_includes ctypes, "image/gif"
      assert_includes ctypes, "image/png"
      assert_includes ctypes, "image/jpeg"
    end

    test "requires a marketplace listing" do
      screenshot = Marketplace::ListingScreenshot.new(marketplace_listing_id: nil)
      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:listing], :present?
    end

    test "requires an uploader" do
      screenshot = Marketplace::ListingScreenshot.new(uploader_id: nil)
      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:uploader], :present?
    end

    test "requires a content type" do
      screenshot = Marketplace::ListingScreenshot.new(content_type: nil)
      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:content_type], :present?
    end

    test "requires a size" do
      screenshot = Marketplace::ListingScreenshot.new(size: nil)
      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:size], :present?
    end

    if GitHub.storage_cluster_enabled?
      test "requires a storage blob" do
        screenshot = Marketplace::ListingScreenshot.new(storage_blob_id: nil)
        refute_predicate screenshot, :valid?
        assert_predicate screenshot.errors[:storage_blob], :present?
      end
    end

    test "requires uploader have permission for integration listing" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      screenshot = build(:marketplace_listing_screenshot, uploader: @user, listing: listing)
      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:uploader], :present?

      screenshot.uploader = integration.owner.admin
      assert_predicate screenshot, :valid?
    end

    test "requires uploader have permission for OAuth app listing" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)
      screenshot = build(:marketplace_listing_screenshot, uploader: @user, listing: listing)
      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:uploader], :present?

      screenshot.uploader = app.user
      assert_predicate screenshot, :valid?
    end

    test "disallows more than 5 screenshots per listing" do
      4.times { create(:marketplace_listing_screenshot, listing: @listing) } # one created in fixtures

      screenshot = build(:marketplace_listing_screenshot, listing: @listing)

      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:listing], :any?
    end

    test "validates length of caption" do
      text = "a" * (Marketplace::ListingScreenshot::CAPTION_MAX_LENGTH + 1)

      screenshot = build(:marketplace_listing_screenshot, listing: @listing, caption: text)

      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:caption], :any?
    end

    test "validates that caption contains only unicode3 characters" do
      text = "🐹" * 5

      screenshot = build(:marketplace_listing_screenshot, listing: @listing, caption: text)

      refute_predicate screenshot, :valid?
      assert_predicate screenshot.errors[:caption], :any?
    end



  end

  context "initialization" do
    test "sets sequence based on existing screenshots for the listing" do
      scr1 = create :marketplace_listing_screenshot
      assert_equal 0, scr1.sequence
      scr2 = create(:marketplace_listing_screenshot, listing: scr1.listing)
      assert_equal 1, scr2.sequence
    end

    test "pulls content type from upload" do
      assert_equal "image/jpeg", @screenshot.content_type
    end

    test "pulls size from upload" do
      assert_equal 1.kilobyte, @screenshot.size
    end

    test "pulls filename from upload" do
      assert_equal "fancy-upload-of-mine.jpg", @screenshot.name
    end

    test "sets raw asset uuid" do
      assert_equal @screenshot, Marketplace::ListingScreenshot.find_by(guid: @screenshot.guid)
    end

    test "starts in state new" do
      assert Marketplace::ListingScreenshot.new.starter?
    end

    test "sets state on upload" do
      assert @screenshot.uploaded?
    end
  end

  context "storage policy" do
    test "uses cdn url if provided" do
      assert_nil GitHub.marketplace_screenshots_cdn_url

      dl_url = @screenshot.storage_policy.download_url
      assert_equal dl_url, @screenshot.storage_external_url

      GitHub.marketplace_screenshots_cdn_url = "https://ml-screens.com/"
      assert_equal "https://ml-screens.com/#{@listing.id}/#{@screenshot.guid}", @screenshot.storage_external_url
    end

    test "delete s3 object without cdn" do
      assert_nil GitHub.marketplace_screenshots_cdn_url

      file = create :marketplace_listing_screenshot
      path = "/#{file.marketplace_listing_id}/#{file.guid}"
      assert_storage_policy_delete(file, path) do
        assert_enqueued_jobs(0, only: [PurgeFastlyUrlJob]) do
          file.destroy
        end
      end
    end

    test "delete s3 object with cdn" do
      GitHub.marketplace_screenshots_cdn_url = "https://ml-screens.com/"

      file = create :marketplace_listing_screenshot
      path = "/#{file.marketplace_listing_id}/#{file.guid}"
      assert_storage_policy_delete(file, path) do
        assert_purge_url file.storage_external_url do
          file.destroy
        end
      end
    end
  end

  context "#resequence" do
    test "moves a screenshot to the beginning of the sequence" do
      listing = create(:marketplace_listing)
      screenshots = 3.times.map { create(:marketplace_listing_screenshot, listing: listing) }

      assert_equal screenshots.map(&:id), listing.screenshots.order(:sequence).pluck(:id)
      screenshots[1].resequence(after_screenshot: nil)
      expected_sequence = screenshots.values_at(1, 0, 2).map(&:id)
      assert_equal expected_sequence, listing.screenshots.order(:sequence).pluck(:id)
    end

    test "moves a screenshot forward to the middle of the sequence" do
      listing = create(:marketplace_listing)
      screenshots = 4.times.map { create(:marketplace_listing_screenshot, listing: listing) }

      assert_equal screenshots.map(&:id), listing.screenshots.order(:sequence).pluck(:id)
      screenshots[0].resequence(after_screenshot: screenshots[2])
      expected_sequence = screenshots.values_at(1, 2, 0, 3).map(&:id)
      assert_equal expected_sequence, listing.screenshots.order(:sequence).pluck(:id)
    end

    test "moves a screenshot backward to the middle of the sequence" do
      listing = create(:marketplace_listing)
      screenshots = 4.times.map { create(:marketplace_listing_screenshot, listing: listing) }

      assert_equal screenshots.map(&:id), listing.screenshots.order(:sequence).pluck(:id)
      screenshots[3].resequence(after_screenshot: screenshots[0])
      expected_sequence = screenshots.values_at(0, 3, 1, 2).map(&:id)
      assert_equal expected_sequence, listing.screenshots.order(:sequence).pluck(:id)
    end

    test "moves a screenshot to the end of the sequence" do
      listing = create(:marketplace_listing)
      screenshots = 3.times.map { create(:marketplace_listing_screenshot, listing: listing) }

      assert_equal screenshots.map(&:id), listing.screenshots.order(:sequence).pluck(:id)
      screenshots[1].resequence(after_screenshot: screenshots[2])
      expected_sequence = screenshots.values_at(0, 2, 1).map(&:id)
      assert_equal expected_sequence, listing.screenshots.order(:sequence).pluck(:id)
    end
  end

  context "#alt_text" do
    context "when there is a caption" do
      test "it returns an empty string" do
        screenshot = create(:marketplace_listing_screenshot, caption: "caption")

        assert_equal "", screenshot.alt_text
      end
    end

    context "when there is no caption" do
      test "it returns the name of the listing followed by 'screenshot'" do
        listing = create(:marketplace_listing, name: "awesome")
        screenshot = create(:marketplace_listing_screenshot, caption: "", listing: listing)

        assert_equal "awesome screenshot", screenshot.alt_text
      end
    end
  end
end
