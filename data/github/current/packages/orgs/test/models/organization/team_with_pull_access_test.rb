# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTeamWithPullAccessTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @team = create(:team, organization: @org, permission: "pull")
  end

  test "knows it has pull access only" do
    assert  @team.pull_only?
    assert  @team.pull?
    assert !@team.push_only?
    assert !@team.admin?
    assert !@team.push?
  end
end
