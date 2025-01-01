# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class OrganizationsTest < Api::SerializerTestCase
  fixtures do
    @rando = create(:user)
    @user = create(:user, plan: "medium")

    @org = create(:organization, admin: @user)
    @org_repo = create(:repository, :minimal, owner: @org)
  end

  context "#organization_hash" do
    test "includes the organization's twitter_username by default" do
      twitter_username = "github"
      create(:profile, user: @org, twitter_username: twitter_username)

      output = T.unsafe(self).organization(@org, full: true)
      assert_equal twitter_username, output["twitter_username"]
    end
  end
end

class OrganizationsMultiTenantTest < Api::SerializerTestCase
  fixtures do
    on_multi_tenant_enterprise do
      @owner = create :emu
      @business = @owner.enterprise_managed_business
      @org = create :organization, business: @business, admin: @owner
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  context "#organization_hash" do
    test "returns display login for external calls" do
      output = T.unsafe(self).organization(@org)

      refute_equal @org.login, @org.display_login
      assert_equal @org.display_login, output["login"]
    end

    test "returns unique login for internal calls" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

      output = T.unsafe(self).organization(@org)

      refute_equal @org.login, @org.display_login
      assert_equal @org.login, output["login"]
    end

    test "does not include collaborators count if org has lots of repos" do
      Organization.stub_const(:MEGA_ORG_REPOS_THRESHOLD, 2) do
        create(:internal_repository, owner: @org, name: "my-first-private-repo")
        output = T.unsafe(self).organization(@org, owner_private: true)
        assert_equal 0, output["collaborators"]
        create(:internal_repository, owner: @org, name: "my-second-private-repo")
        output = T.unsafe(self).organization(@org.reload, owner_private: true)
        assert_nil output["collaborators"]
      end
    end
  end
end unless GitHub.single_business_environment?
