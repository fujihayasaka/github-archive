# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTeamWithAdminAccessTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @team = create(:team, organization: @org, permission: "admin")
  end

  test "knows it has admin access" do
    assert !@team.pull_only?
    assert !@team.push_only?
    assert  @team.admin?
    assert  @team.pull?
    assert  @team.push?
  end
end
