# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsDeleteSponsorsTierTest < GitHub::TestCase
  fixtures do
    @sponsors_listing = create(:sponsors_listing)
    @sponsorable = @sponsors_listing.sponsorable
  end

  context "sponsors tier deletion" do
    test "sponsorable deletes a draft tier" do
      tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsors_listing)

      Sponsors::DeleteSponsorsTier.call(tier: tier, viewer: @sponsorable)

      refute SponsorsTier.exists?(tier.id)
    end

    test "raises error when non-sponsorable attempts to delete a draft tier" do
      other_user = create(:user)
      tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::DeleteSponsorsTier::ForbiddenError do
        Sponsors::DeleteSponsorsTier.call(tier: tier, viewer: other_user)
      end
      assert_equal "#{other_user.login} does not have permission to delete the tier.", error.message
    end

    test "raises error when deleting a published tier on an approved listing" do
      @sponsors_listing.update!(state: :approved)
      tier = create(:sponsors_tier, :published, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::DeleteSponsorsTier::ForbiddenError do
        Sponsors::DeleteSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "#{@sponsorable.login} does not have permission to delete the tier.", error.message
    end

    test "raises error when deleting a retired tier on an approved listing" do
      @sponsors_listing.update!(state: :approved)
      tier = create(:sponsors_tier, :retired, sponsors_listing: @sponsors_listing)

      error = assert_raises Sponsors::DeleteSponsorsTier::ForbiddenError do
        Sponsors::DeleteSponsorsTier.call(tier: tier, viewer: @sponsorable)
      end
      assert_equal "#{@sponsorable.login} does not have permission to delete the tier.", error.message
    end
  end
end unless GitHub.enterprise?
