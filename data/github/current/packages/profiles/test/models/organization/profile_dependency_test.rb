# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationProfileDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  context "create_org_profile_readme" do
    test "returns private organization profile when type is member", skip_enterprise: true do
      private_profile = @org.create_org_profile_readme(type: "member")

      assert_equal private_profile.public?, false
    end

    test "returns public organization profile when type is public", skip_enterprise: true do
      public_profile = @org.create_org_profile_readme(type: "public")

      assert_equal public_profile.public?, true
    end

    test "returns public organization profile when type is other", skip_enterprise: true do
      public_profile = @org.create_org_profile_readme(type: "bananas")

      assert_equal public_profile.public?, true
    end
  end
end
