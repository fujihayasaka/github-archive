# typed: true
# frozen_string_literal: true

require "test_helper"

class FinancialOnboardingDependencyTest < GitHub::TestCase
  include Marketplace::FinancialOnboardingDependency
  fixtures do
    @github = create(:organization, login: "github")
    @listing_unverified = create(:marketplace_listing, :unverified)
    @listing_draft = create(:marketplace_listing, :draft, name: "Test App", slug: "testapp")
  end

  test "update_issue_content replaces APPNAME and APPSLUG with listing name and slug" do
    dummy_content = "This is a dummy text with dummy [APPNAME] and dummy [APPSLUG]"
    @listing_unverified.name = "Test App"
    @listing_unverified.slug = "testapp"
    dummy_content = update_issue_content(dummy_content, @listing_unverified.name, @listing_unverified.slug)
    assert_equal dummy_content, "This is a dummy text with dummy Test App and dummy testapp"
  end

  test "find_template_issue returns issue template string for unverified listing" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    @unverified_issue = create(:issue, repository: @repo, number: 162, title: "Test for", body: "test for body")
    issue = find_template_issue("unverified_listing", @repo.id)
    assert_equal issue, "onboard-paid-app-pending-from-unverified.md"
  end

  test "find_template_issue return issue template string for draft listing" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    @draft_issue = create(:issue, repository: @repo, number: 158, title: "Test for", body: "test for body")
    issue = find_template_issue("new_listing", @repo.id)
    assert_equal issue, "onboard-paid-app-pending-from-draft.md"
  end

  test "find_template_issue logs event and returns when issue is not found" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    issue = find_template_issue("unverified_pending", @repo.id)
    assert_nil issue
  end

  test "create_issue_from_state returns issue template name if listing is not spam" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    @draft_issue = create(:issue, repository: @repo, number: 158, title: "Test for [APPNAME]", body: "test for body [APPNAME] [APPSLUG]")
    @listing_draft.name = "Test App"
    @listing_draft.slug = "testapp"
    issue = create_issue_from_state("new_listing", @listing_draft.name, @listing_draft.slug, @repo.id)
    assert_equal issue, "onboard-paid-app-pending-from-draft.md"
  end

  test "create_issue_from_state returns nil when issue is not found" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    @listing_unverified.name = "Test App"
    @listing_unverified.slug = "testapp"
    issue = create_issue_from_state("spammy_listing", @listing_unverified.name, @listing_unverified.slug, @repo.id)
    assert_nil issue
  end

  test "find_repository returns repo when found" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    repo = find_repository
    assert_equal repo.name, @repo.name
  end

  test "find_repository returns nil when repo not found" do
    repo = find_repository
    assert_nil repo
  end

  test "create_issue_in_marketplace returns nil when repo is not found" do
    issue = create_issue_in_marketplace("new_listing", @listing_draft.name, @listing_draft.slug)
    assert_nil issue
  end

  test "create_issue_in_marketplace returns nil when issue template is not found" do
    @repo = create(:private_repository, name: "marketplace", owner: @github)
    issue = create_issue_in_marketplace("new_listing", @listing_draft.name, @listing_draft.slug)
    assert_nil issue
  end
end
