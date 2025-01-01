# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../test_organization_orchestration"

class OrganizationOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)

    @user = create(:user)

    @business_owner = create(:user)
    @business_org = create(:organization, admin: @business_owner)
    @business = create(:business, organizations: [@business_org], owners: [@business_owner])

    @orchestration = TestOrganizationOrchestration.create(actor: @owner, business_id: @business.id, organization_ids: [@org.id], team_ids: [], user_ids: [@user.id], data: { is_test: true })
  end

  test "base_orchestration_name" do
    assert_equal "organization_orchestration", OrganizationOrchestration.base_orchestration_name
    assert_equal "organization_orchestration", OrganizationOrchestration.new.base_orchestration_name
  end

  context "organization_ids" do
    test "encodes and decodes ids" do
      o = AddUsersOrganizationOrchestration.create(actor: @owner, organization_ids: [1, 1000])
      assert_equal [1, 1000], o.organization_ids
    end
  end

  context "team_ids" do
    test "encodes and decodes ids" do
      o = AddUsersOrganizationOrchestration.create(actor: @owner, team_ids: [1, 1000])
      assert_equal [1, 1000], o.team_ids
    end
  end

  context "user_ids" do
    test "encodes and decodes ids" do
      o = RemoveUsersOrganizationOrchestration.create(actor: @owner, user_ids: [1, 1000])
      assert_equal [1, 1000], o.user_ids
    end
  end

  context "datadog_tags" do
    test "adds tag orchestration_staff_owned:false when not staff owned" do
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user], business_id: @business.id).execute(synchronous: true)
      assert_dogstats_increment(1, "organization_orchestration.completed", tags: ["orchestration_staff_owned:false"])
    end

    test "adds tag orchestration_staff_owned:true when staff owned" do
      @business.update(staff_owned: true)
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user], business_id: @business.id).execute(synchronous: true)
      assert_dogstats_increment(1, "organization_orchestration.completed", tags: ["orchestration_staff_owned:true"])
    end

    test "adds tag orchestration_business_team:false when not run with business_team_action" do
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user], business_id: @business.id, business_team_action: false).execute(synchronous: true)
      assert_dogstats_increment(1, "organization_orchestration.completed", tags: ["orchestration_business_team:false"])
    end

    test "adds tag orchestration_business_team:true when run with business_team_action" do
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user], business_id: @business.id, business_team_action: true).execute(synchronous: true)
      assert_dogstats_increment(1, "organization_orchestration.completed", tags: ["orchestration_business_team:true"])
    end

    test "adds tag orchestration_batch_action:false when run with one user and organization" do
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user], business_id: @business.id).execute(synchronous: true)
      assert_dogstats_increment(1, "organization_orchestration.completed", tags: ["orchestration_batch_action:false"])
    end

    test "adds tag orchestration_batch_action:true when run with multiple organizations" do
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org, @org], teams: [], users: [@user], business_id: @business.id, business_team_action: true).execute(synchronous: true)
      assert_dogstats_increment(1, "organization_orchestration.completed", tags: ["orchestration_batch_action:true"])
    end

    test "adds tag orchestration_batch_action:true when run with multiple users" do
      OrganizationOrchestration.add_users(actor: @owner, organizations: [@business_org], teams: [], users: [@user, @business_owner], business_id: @business.id, business_team_action: true).execute(synchronous: true)
      assert_dogstats_increment(1, "organization_orchestration.completed", tags: ["orchestration_batch_action:true"])
    end
  end
end
