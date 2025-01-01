# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryConfigurationRepoDependencyTest < GitHub::TestCase
  context "#is_org_profile_repository?" do
    test "true when public, has the right name and owned by an org" do
      org = create(:organization)
      repo = create(:repository, owner: org, name: ".github")

      assert_predicate repo, :is_org_profile_repository?
    end

    test "false if private" do
      org = create(:organization)
      repo = create(:private_repository, owner: org, name: ".github")

      refute_predicate repo, :is_org_profile_repository?
    end

    test "false when the name is incorrect" do
      org = create(:organization)
      repo = create(:repository, owner: org, name: ".notright")

      refute_predicate repo, :is_org_profile_repository?
    end
  end

  context "org_profile_readme" do
    test "returns the file at /profile/README.md if this is an org's .github repo" do
      org = create(:organization)
      repo = create(:repository, owner: org, name: ".github", from_example: :org_profile)
      assert repo.org_profile_readme
      assert repo.has_org_profile_readme?
    end

    test "returns false if the org does not have a .github repo" do
      org = create(:organization)
      repo = create(:repository, owner: org, name: "nothub", from_example: :org_profile)
      assert_nil repo.org_profile_readme
      refute repo.has_org_profile_readme?
    end
  end

  context "generate_org_profile_readme" do
    test "returns the template if this is the org's .github repo" do
      org = create(:organization)
      repo = create(:repository, owner: org, name: ".github")
      assert_match /Hi there/, repo.generate_org_profile_readme
    end

    test "returns an empty string if this is not the org's .github repo" do
      org = create(:organization)
      repo = create(:repository, owner: org, name: "somethingelse")
      assert_equal "", repo.generate_org_profile_readme
    end
  end

  context "#user_configuration_repository?" do
    test "true when has the right name and owned by a user" do
      user = create(:user)
      repo = create(:repository, owner: user, name: user.config_repo_name)

      assert_predicate repo, :user_configuration_repository?
    end

    test "true for private repo with the right name and owned by a user" do
      user = create(:user)
      repo = create(:private_repository, owner: user, name: user.config_repo_name)

      assert_predicate repo, :user_configuration_repository?
    end

    test "false when owned by a user but has the wrong name" do
      user = create(:user)
      repo = create(:repository, owner: user, name: "SomeOtherName")

      refute_predicate repo, :user_configuration_repository?
    end

    test "false when has the right name but owned by an org" do
      org = create(:organization)
      repo = create(:repository, owner: org, name: org.config_repo_name)

      refute_predicate repo, :user_configuration_repository?
    end

    test "is case-insensitive" do
      user = create(:user)
      repo = create(:private_repository, owner: user, name: user.config_repo_name.upcase)

      assert_predicate repo, :user_configuration_repository?
    end
  end
end
