# typed: true
# frozen_string_literal: true

require "test_helper"

class HovercardDependencyForSponsorsListingTest < GitHub::TestCase
  fixtures do
    @sponsors_listing = create(:sponsors_listing, :approved)
    @sponsorable = @sponsors_listing.sponsorable
    @viewer = create(:user)
  end

  context "your_sponsor context" do
    if GitHub.sponsors_enabled?
      test "returns a context as if the viewer were sponsoring the listing's sponsorable" do
        context = @sponsors_listing.user_hovercard_context_for(@viewer,
          viewer: @viewer, limit: :your_sponsor)

        refute_nil context
        refute_predicate context, :private_sponsor?
      end

      test "returns nil when requested user is not the viewer" do
        context = @sponsors_listing.user_hovercard_context_for(@sponsorable,
          viewer: @viewer, limit: :your_sponsor)

        assert_nil context
      end
    else
      test "returns nil when Sponsors is disabled" do
        context = @sponsors_listing.user_hovercard_context_for(@viewer,
          viewer: @viewer, limit: :your_sponsor)

        assert_nil context
      end
    end
  end
end
