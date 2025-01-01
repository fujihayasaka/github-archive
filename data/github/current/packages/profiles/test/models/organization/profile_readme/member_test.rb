# typed: true
# frozen_string_literal: true

require "test_helper"

class MemberOrganizationProfileTest < GitHub::TestCase
  setup do
    @org = create(:organization)
  end

  context "repository" do
    test "returns the org's .github-private repo" do
      repo = create(:private_repository, owner: @org, name: ".github-private", from_example: :org_member_profile)
      profile = @org.create_org_profile_readme(type: "member")

      assert profile.repository
      assert_equal profile.repository, repo
    end

    test "returns false if the org does not have a .github-private repo" do
      repo = create(:private_repository, owner: @org, name: "nothub", from_example: :org_member_profile)
      profile = @org.create_org_profile_readme(type: "member")

      assert_nil profile.repository
    end
  end

  context "readme" do
    test "returns the file at /profile/README.md from the org's .github-private repo" do
      repo = create(:private_repository, owner: @org, name: ".github-private", from_example: :org_member_profile)
      profile = @org.create_org_profile_readme(type: "member")

      assert profile.readme
      assert_equal profile.readme, repo.org_member_profile_readme
      assert_equal profile.readme.path, "profile/README.md"
    end

    test "returns false if the org does not have a .github repo" do
      repo = create(:private_repository, owner: @org, name: "nothub", from_example: :org_member_profile)
      profile = @org.create_org_profile_readme(type: "member")

      assert_nil profile.readme
    end
  end

  context "visible?" do
    test "profile is visible if repo is not disabled" do
      repo = create(:private_repository, owner: @org, name: ".github-private", from_example: :org_member_profile)
      profile = @org.create_org_profile_readme(type: "member")

      assert profile.visible?
    end

    if GitHub.spamminess_check_enabled?
      test "profile is not visible if org is spammy" do
        @org.mark_as_spammy
        repo = create(:private_repository, owner: @org, name: ".github-private", from_example: :org_member_profile)
        profile = @org.create_org_profile_readme(type: "member")

        refute profile.visible?
      end
    end

    test "profile not visible if repo disabled" do
      repo = create(:private_repository, owner: @org, name: ".github-private", disabled_at: Time.now, disabling_reason: "dmca", from_example: :org_member_profile)
      profile = @org.create_org_profile_readme(type: "member")

      refute profile.visible?
    end

  end
end
