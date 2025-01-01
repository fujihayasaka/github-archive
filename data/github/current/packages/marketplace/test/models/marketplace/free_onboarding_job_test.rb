# typed: true
# frozen_string_literal: true

require "test_helper"

class FreeOnboardingJobTest < GitHub::TestCase

  fixtures do

    @github = create(:organization, login: "github")
    @listing_unverified_pending = create(:marketplace_listing, :unverified_pending)
    @user = create(:user, login: "Marketplace-Bot")
    @listing_draft = create(:marketplace_listing, :unverified_pending, name: "Test App", slug: "testapp")
  end

  context "perform" do
    test "create_issue_in_marketplace succesfully creates a new issue for unverified_pending listing, and new issue includes updaates title and body with feature flag enabled" do
      @repo = create(:private_repository, name: "marketplace", owner: @github, from_example: :simple)
      enable_feature_flag(:marketplace_create_free_app_verification_onboarding_issues, @github)

      commit = @repo.commits.create({ message: "Add templates", committer: @github }) do |files|
        files.add ".github/ISSUE_TEMPLATE/onboard-free-app-unverified-pending.md", <<~MARKDOWN
        ---
        name: Template for Onboarding Unverified Pending Apps (Free)", about: "Tracking issue for onboarding Unverified Pending Apps on GitHub Marketplace
        about: Tracking issue for onboarding Unverified Pending Apps on GitHub Marketplace
        title: Onboarding Unverified Pending App (Free) - [App Name]
        ---
        Application Name - [App Name]
        MARKDOWN
      end
      @repo.refs["refs/heads/master"].update(commit, @user)

      issue_count = Issue.count
      expected_count = issue_count + 1

      IssueTemplates.any_instance.stubs(:templates_by_filename).returns({ "onboard-free-app-unverified-pending.md" => Issue.new(title: "Onboarding Unverified Pending App (Free) - [App Name]", body: "Tracking issue for onboarding Unverified Pending Apps on GitHub Marketplace. **Biztool link** - ") })

      FreeOnboardingJob.perform_now("new_listing", @listing_draft.name, @listing_draft.slug)

      assert_equal expected_count, Issue.count

      new_issue = Issue.last
      new_issue_title = T.must(new_issue).title
      new_issue_body = T.must(new_issue).body

      refute_includes new_issue_title, "[App Name]"
      assert_includes new_issue_body, "https://admin.github.com/biztools/marketplace/#{@listing_draft.slug}"
    end
  end

  test "find_repository returns repo when found" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    repo = FreeOnboardingJob.new.find_repository
    assert_equal repo.name, @repo.name
  end

  test "find_repository returns nil when repo not found" do
    @repo = nil
    repo = FreeOnboardingJob.new.find_repository
    assert_nil repo
  end

  test "create_issue_in_marketplace returns nil when repo is not found" do
    @repo = nil
    issue = FreeOnboardingJob.new.create_issue_in_marketplace("new_listing", @listing_draft.name, @listing_draft.slug)
    assert_nil issue
  end

  test "create_issue_in_marketplace returns nil when issue template is not found" do
    @repo = create(:public_repository, name: "marketplace", owner: @github)
    issue = FreeOnboardingJob.new.create_issue_in_marketplace("new_listing", @listing_draft.name, @listing_draft.slug)
    assert_nil issue
  end
end
