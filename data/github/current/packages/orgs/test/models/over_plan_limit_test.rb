# typed: true
# frozen_string_literal: true

require "test_helper"

class OverPlanLimitTest < GitHub::TestCase
  test "returns false for per seat plans" do
    org = create :organization, plan: GitHub::Plan.business

    org.expects(:private_repo_count_for_limit_check).never

    refute org.over_plan_limit?
  end

  test "returns true for user over the plan repo limit" do
    user = create :user
    create_list :private_repository, 6, owner: user
    user.update plan: "micro"

    assert user.reload.over_plan_limit?
  end

  test "returns true for orgs over the plan repo limit" do
    org = create :organization, plan: "silver"
    11.times { create :private_repository, :minimal, owner: org }
    org.update plan: "bronze"

    assert org.reload.over_plan_limit?
  end
end if GitHub.billing_enabled?
