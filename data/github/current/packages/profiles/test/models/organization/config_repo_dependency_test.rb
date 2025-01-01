# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationConfigRepoDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization, name: "TestOrg")
  end

  context "private_configuration_repository relation" do
    test "does not return the public config repo for the org" do
      repo = create(:repository, owner: @org, name: Organization::ConfigRepoDependency::CONFIG_REPO_NAME)
      assert_nil @org.private_configuration_repository
    end

    test "returns the private config repo for the org" do
      repo = create(:private_repository, owner: @org, name: Organization::ConfigRepoDependency::CONFIG_PRIVATE_REPO_NAME)
      assert_equal repo, @org.private_configuration_repository
    end
  end

  context "#has_configuration_repository?" do
    test "returns false if the org does not own a .github repo" do
      assert_nil @org.configuration_repository
      refute @org.has_configuration_repository?
    end

    test "returns false if the org owns a private .github repo" do
      repo = create(:private_repository, owner: @org, name: ".github")
      assert_nil @org.configuration_repository
      refute @org.has_configuration_repository?
    end

    test "returns true if the org owns a public .github repo" do
      repo = create(:repository, owner: @org, name: ".github")
      assert_equal repo.id, @org.configuration_repository.id
      assert @org.has_configuration_repository?
    end
  end

  test "config_repo_name is always .github" do
    assert_equal ".github", @org.config_repo_name
  end
end
