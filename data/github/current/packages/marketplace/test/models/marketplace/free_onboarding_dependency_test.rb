# typed: true
# frozen_string_literal: true

require "test_helper"

class FreeOnboardingDependencyTest < GitHub::TestCase
  context "#initiate_free_onboarding" do
    test "enquques FreeOnboardingJob when an draft listing is transitioned op unverified app initiates financial onboarding" do
      @github = create(:organization, login: "github")
      org = create(:organization)
      @repo = create(:private_repository, name: "marketplace", owner: @github)
      user = create(:user, login: "Marketplace-Bot")

      integration = create(:integration, owner: org)
      listing = create(
        :marketplace_listing_ready_for_review,
        :verified_publisher,
        :unverified_pending,
        listable: integration,
      )
      Repository.any_instance.stubs(:issue_templates).returns({ "onboard-free-app-unverified-pending.md" => Issue.new(title: "Onboarding Unverified Pending App (Free) - [APPNAME]", body: "Tracking issue for onboarding Unverified Pending Apps on GitHub Marketplace") })

      assert_equal(0, Issue.count)
      listing.initiate_free_onboarding("new_listing", listing.name, listing.slug)
      assert_equal(1, Issue.count)
    end
  end
end
