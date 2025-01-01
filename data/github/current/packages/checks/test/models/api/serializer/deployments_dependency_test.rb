# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class DeploymentsTest < Api::SerializerTestCase
  fixtures do
    @deployment = create(:deployment)
  end

  context "#deployment_hash" do
    test "payload is valid" do
      output = deployment(@deployment)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("task")
      assert output.key?("original_environment")
    end

    test "payload is valid via app" do
      deployment_created_by_app = create(:deployment, :via_app)
      output = deployment(deployment_created_by_app)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("task")
      assert output.key?("original_environment")
    end

    test "payload is valid when deployment was not created by integration" do
      output = deployment(@deployment)
      assert output.key?("id")
      assert output.key?("node_id")
      assert output.key?("task")
      assert output.key?("original_environment")
    end
  end
end

class DeploymentsMultiTenantTest < Api::SerializerTestCase
  fixtures do
    on_multi_tenant_enterprise do
      @emu = create :emu, :owner
      @business = @emu.enterprise_managed_business
      @org = create :organization, business: @business
      @repo = create :repository, organization: @org
      @deployment = create :deployment, repository: @repo
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  context "#simple_deployment_hash" do
    test "payload returns url with display login value for external calls" do
      output = simple_deployment(@deployment)
      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_display_owner
    end

    test "payload returns url with unqiue login value for internal calls" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

      output = simple_deployment(@deployment)
      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_owner
    end
  end
end unless GitHub.single_business_environment?
