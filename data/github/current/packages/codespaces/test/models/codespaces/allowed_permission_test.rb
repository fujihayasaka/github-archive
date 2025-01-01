# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesAllowedPermissionTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  context "validations" do
    test "ensure presence checks" do
      allowed_permission = Codespaces::AllowedPermission.new

      refute allowed_permission.valid?
      refute_nil allowed_permission.errors[:repository]
      refute_nil allowed_permission.errors[:user]
      refute_nil allowed_permission.errors[:resource]
      refute_nil allowed_permission.errors[:action]
      refute_nil allowed_permission.errors[:target_id]
      refute_nil allowed_permission.errors[:target_type]
    end

    test "saves with valid data" do
      allowed_permission = Codespaces::AllowedPermission.new \
        repository: @repo,
        user: @user,
        target_id: @repo.id,
        target_type: :repository,
        resource: "contents",
        action: :read
    end

    test "resource must belong to list of available resources for permissions" do
      allowed_permission = Codespaces::AllowedPermission.new \
        repository: @repo,
        user: @user,
        target_id: @repo.id,
        target_type: :repository,
        resource: "contents",
        action: :read

      refute allowed_permission.valid?
      refute_nil allowed_permission.errors[:resource]
    end
  end
end
