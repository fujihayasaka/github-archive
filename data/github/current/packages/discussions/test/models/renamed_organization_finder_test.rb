# typed: true
# frozen_string_literal: true

require "test_helper"
class RenamedOrganizationFinderTest < GitHub::TestCase

  test "returns the renamed org if a RepositoryRedirect exists for an active repo in the org" do
    org = create(:organization, login: "renamed-org")
    repo = create(:repository, owner: org, name: "repo")
    create(:repository_redirect, repository: repo, repository_name: "org/repo")
    assert_equal org, RenamedOrganizationFinder.for_original_name("org")
  end

  test "returns nil if the org doesn't exist and hasn't been renamed" do
    org = create(:organization, login: "org")
    refute RenamedOrganizationFinder.for_original_name("other-org")
  end

  test "returns nil if the org exists but hasn't been renamed" do
    org = create(:organization, login: "org")
    refute RenamedOrganizationFinder.for_original_name("org")
  end

  test "returns nil if the repo is not active" do
    org = create(:organization, login: "renamed-org")
    repo = create(:repository, owner: org, name: "repo", active: false)
    create(:repository_redirect, repository: repo, repository_name: "org/repo")
    refute RenamedOrganizationFinder.for_original_name("org")
  end
end
