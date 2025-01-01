# typed: true
# frozen_string_literal: true

require "test_helper"

class PublicOrganizationProfileTest < GitHub::TestCase
  setup do
    @org = create(:organization)
  end

  context "repository" do
    test "returns the org's .github repo" do
      repo = create(:repository, owner: @org, name: ".github", from_example: :org_profile)
      profile = @org.create_org_profile_readme(type: "public")

      assert profile.repository
      assert_equal profile.repository, repo
      assert_equal repo, profile.async_repository.sync
    end

    test "returns nil if the org does not have a .github repo" do
      repo = create(:repository, owner: @org, name: "nothub", from_example: :org_profile)
      profile = @org.create_org_profile_readme(type: "public")

      assert_nil profile.repository
      assert_nil profile.async_repository.sync
    end
  end

  context "readme" do
    test "returns the file at /profile/README.md from the org's .github repo" do
      repo = create(:repository, owner: @org, name: ".github", from_example: :org_profile)
      profile = @org.create_org_profile_readme(type: "public")

      assert profile.readme
      assert_equal profile.readme, repo.org_profile_readme
      assert_equal profile.readme.path, "profile/README.md"
    end

    test "returns false if the org does not have a .github repo" do
      repo = create(:repository, owner: @org, name: "nothub", from_example: :org_profile)
      profile = @org.create_org_profile_readme(type: "public")

      assert_nil profile.readme
    end
  end

  context "visible?" do
    test "profile is visible if repo is not disabled" do
      repo = create(:repository, owner: @org, name: ".github", from_example: :org_profile)
      profile = @org.create_org_profile_readme(type: "public")

      assert profile.visible?
      assert profile.async_visible?.sync
    end

    if GitHub.spamminess_check_enabled?
      test "profile is not visible if org is spammy" do
        @org.mark_as_spammy
        repo = create(:repository, owner: @org, name: ".github", from_example: :org_profile)
        profile = @org.create_org_profile_readme(type: "public")

        refute profile.visible?
        refute profile.async_visible?.sync
      end
    end

    test "profile not visible if repo disabled" do
      repo = create(:repository, owner: @org, name: ".github", disabled_at: Time.now, disabling_reason: "dmca", from_example: :org_profile)
      profile = @org.create_org_profile_readme(type: "public")

      refute profile.visible?
      refute profile.async_visible?.sync
    end
  end
end
