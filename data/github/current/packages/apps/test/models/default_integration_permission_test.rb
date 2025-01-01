# typed: true
# frozen_string_literal: true

require "test_helper"

class DefaultIntegrationPermissionOnAnIntegrationTest < GitHub::TestCase
  fixtures do
    integration = create(:integration, default_permissions: { "contents" => :read })
    @version = integration.latest_version
  end

  context "validations" do
    test "resource must be unique per integration_id" do
      permission = DefaultIntegrationPermission.create \
        resource: "issues",
        action: 0,
        integration_version_id: @version.id

      dupe = DefaultIntegrationPermission.create \
        resource: "issues",
        action: 0,
        integration_version_id: @version.id

      assert_predicate permission, :valid?
      refute_predicate dupe, :valid?
      refute_empty dupe.errors[:resource]
    end

    test "resource can be an Organization based resource" do
      permission = DefaultIntegrationPermission.create \
        resource: "members",
        action: 0,
        integration_version_id: @version.id

      assert_predicate permission, :valid?
    end

    test "resource can be an User based resource" do
      permission = DefaultIntegrationPermission.create \
        resource: User::Resources.subject_types.first,
        action: 0,
        integration_version_id: @version.id

      assert_predicate permission, :valid?
    end

    test "resource required" do
      permission = DefaultIntegrationPermission.new
      refute_predicate permission, :valid?
      refute_empty permission.errors[:resource]
    end

    test "action required" do
      permission = DefaultIntegrationPermission.new
      refute_predicate permission, :valid?
      refute_empty permission.errors[:action]
    end

    test "resource must be valid" do
      permission = DefaultIntegrationPermission.create \
        resource: "bogus_stuff",
        action: 0,
        integration_version_id: @version.id

      refute_predicate permission, :valid?
      refute_empty permission.errors[:resource]
    end

    test "resource cannot be set to write if it is a read only permission" do
      permission = DefaultIntegrationPermission.create \
        resource: "metadata",
        action: 1,
        integration_version_id: @version.id

      refute_predicate permission, :valid?
      assert_same_elements ["has already been taken", "(metadata) is a read-only permission"], permission.errors[:resource]
    end

    test "resource cannot be set to read if it is a write only permission" do
      permission = DefaultIntegrationPermission.create \
        resource: "workflows",
        action: 0,
        integration_version_id: @version.id

      refute_predicate permission, :valid?
      assert_same_elements ["(workflows) is a write-only permission"], permission.errors[:resource]
    end

    test "resource cannot be set to admin unless on the allowlist" do
      permission = DefaultIntegrationPermission.create \
        resource: "issues",
        action: 2,
        integration_version_id: @version.id

      refute_predicate permission, :valid?
      assert_same_elements ["(issues) is not permitted to have admin access"], permission.errors[:resource]
    end
  end

  test "sets the integration id as the integration_version_id" do
    integration = @version.integration
    @version.default_permission_records.each do |permission_record|
      assert_equal integration.id, permission_record.integration_id
    end
  end
end
