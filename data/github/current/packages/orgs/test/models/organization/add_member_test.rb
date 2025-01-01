# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAddMemberTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @org = create(:organization)
    @user = create(:user)
  end


  test "instruments membership event to hydro", skip_enterprise: true do
    GitHub.hydro_publisher.sink&.messages&.clear

    @org.add_member(@user)
    assert_hydro_messages(count: 1, schema: "github.v1.MembershipUpdate")
  end

  test "performs the create immediately/synchronously" do
    @org.add_member(@user, action: :admin)
    assert @org.adminable_by?(@user), "member should have been granted admin on the org"
  end

  test "user added as admin to org has admin ability on org and its dependents" do
    project = create(:project, name: "Dependent", owner: @org)
    refute project.adminable_by?(@user)
    @org.add_member(@user, action: :admin)

    assert @org.adminable_by?(@user), "member should have been granted admin on the org"
    assert project.adminable_by?(@user), "member should have admin on owner ability over the project"
  end
end
