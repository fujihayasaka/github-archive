# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationMembersExportTest < GitHub::TestCase
  # include AuditLogHelpers

  fixtures do
    @actor = create(:user)
    @org = create(:organization)
  end

  setup do
    @azure_client = mock("azure client")
    @azure_client.stubs(:create_block_blob)
    GHECAdmin::AzureStorage.any_instance.stubs(:azure_blob_client).returns(@azure_client)
  end

  test "storage uses azure backend" do
    export = OrganizationMembersExport.create({
      subject: @org,
      actor: @actor,
    })
    assert export.storage.instance_of?(GHECAdmin::AzureStorage)
  end

  test "can be created without phrase" do
    assert_difference "OrganizationMembersExport.count" do
      OrganizationMembersExport.create({
        subject: @org,
        actor: @actor,
      })
    end
  end

  test "generates unique token for export request" do
    export = OrganizationMembersExport.create({
      subject: @user,
      actor: @actor,
    })

    assert export.token?, "expected token to be generated"
  end

  test "format must be json or csv" do
    export = OrganizationMembersExport.new({
      subject: @org,
      actor: @actor,
      format: "json",
    })
    assert export.valid?

    export.format = "csv"
    assert export.valid?

    export.format = "png"
    refute export.valid?
  end

  test "json content type is determined by format" do
    export = create(:organization_members_export, format: "json")
    assert_equal "application/json", export.content_type
  end

  test "csv content type is determined by format" do
    export = create(:organization_members_export, format: "csv")
    assert_equal "text/csv", export.content_type
  end

  test "unique token generated doesn't clash with same export request" do
    export1 = OrganizationMembersExport.create({
      subject: @org,
      actor: @actor,
    })
    export2 = OrganizationMembersExport.create({
      subject: @org,
      actor: @actor,
    })

    refute_equal export1.token, export2.token
  end

  test "returns token for parameter after validation" do
    export = OrganizationMembersExport.new({
      subject: @org,
      actor: @actor,
    })

    assert_predicate export, :valid?
    assert_equal export.to_param, export.token
  end

  test "is created without the site admin context by default" do
    export = create(:organization_members_export, format: "csv")
    refute_predicate export, :for_site_admin?
  end

  test "can be created for the site admin context" do
    export = create(:organization_members_export, format: "csv", for_site_admin: true)
    assert_predicate export, :for_site_admin?
  end
end
