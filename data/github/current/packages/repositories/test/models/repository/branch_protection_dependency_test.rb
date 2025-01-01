# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryBranchProtectionDependencyTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @protected_branch = create(:protected_branch, repository: @repo, name: "main")
  end

  context "branch_protection_for" do
    test "returns the protected branch when branch protection exists" do
      assert_equal @protected_branch, @repo.branch_protection_for("main")
    end

    test "returns nil when branch protection does not exist" do
      assert_nil @repo.branch_protection_for("notprotectedbranch")
    end
  end

  context "branch_protected?" do
    test "returns true if branch is protected" do
      assert @repo.branch_protection_for("main")
    end

    test "returns false if branch is not protected" do
      refute @repo.branch_protection_for("notprotectedbranch")
    end
  end
end
