# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class MigrationsTest < Api::SerializerTestCase
  fixtures do
    @user = create(:user, plan: "medium")
  end

  context "#migration_hash" do
    test "for org returns the proper url path" do
      org = create(:organization, admin: @user)
      migration = create(:migration, owner: org)
      org_path = "/orgs/#{org}/migrations/"
      output = T.unsafe(self).migration(migration, full: true)

      assert_includes output["url"], org_path
    end

    test "for user returns the proper url path" do
      migration = create(:migration, owner: @user)
      user_path = "/user/migrations/"
      output = T.unsafe(self).migration(migration, full: true)

      assert_includes output["url"], user_path
    end
  end
end

class MigrationsMultiTenantTest < Api::SerializerTestCase
  fixtures do
    on_multi_tenant_enterprise do
      GitHub.flipper[:tenant_namespacing].enable
      @owner = create :emu
      @business = @owner.enterprise_managed_business
      @org = create :organization, business: @business, admin: @owner
      @migration = create(:migration, owner: @org)
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  context "#migration_hash" do
    test "for multitenant does not return shortcode in the url" do
      output = T.unsafe(self).migration(@migration, full: true)

      refute_includes output["url"], @business.shortcode
    end
  end
end unless GitHub.single_business_environment?
