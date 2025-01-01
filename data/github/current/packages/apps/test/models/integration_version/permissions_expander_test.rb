# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationVersion::PermissionsExpanderTest < GitHub::TestCase
  context "Business resources" do
    test "returns the correct subject types" do
      assert_equal ["Business/enterprise_administration"], expand({ "enterprise_administration" => :read })
    end
  end

  context "Organization resources" do
    test "returns the correct subject types" do
      assert_equal ["Organization/members"], expand({ "members" => :read })
    end
  end

  context "Repository resources" do
    test "returns the individual ability prefix subject types" do
      assert_includes expand({ "metadata" => :read }), "Repository/metadata"
    end

    test "returns the all ability prefix subject types" do
      assert_includes expand({ "metadata" => :read }), "User/repositories/metadata"
    end
  end

  context "User resources" do
    test "returns the correct subject types" do
      assert_includes expand({ "emails" => :read }), "User/emails"
    end
  end

  context "Mixed resources" do
    test "returns all expected subject types" do
      expected = [
        "User/repositories/metadata",
        "Repository/metadata",
        "Organization/members",
        "User/starring",
      ]

      assert_equal expected, expand({ "metadata" => :read, "members" => :write, "starring" => :read })
    end
  end

  private def expand(permissions)
    IntegrationVersion::PermissionsExpander.expand(permissions)
  end
end
