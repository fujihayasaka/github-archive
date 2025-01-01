# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::KeepTest < GitHub::TestCase
  setup do
    GitHub.flipper[:codespaces_keep].enable
  end

  test "can keep a user-owned codespace" do
    codespace = create(:codespace, keep: false, retention_period_minutes: 180)

    cmd = Codespaces::Keep.new(codespace)
    assert cmd.can_keep?
    cmd.perform
    assert codespace.reload.keep?
  end

  test "can keep an org-owned codespace" do
    user = create(:user)
    org = create(:codespaces_organization, admin: user)
    org_repo = create(:private_repository, owner: org)
    org.add_member(user)

    codespace = create(:codespace,
      owner: user,
      repository: org_repo,
      billable_owner: org,
      retention_period_minutes: 2.days.in_minutes.to_i)

    cmd = Codespaces::Keep.new(codespace)
    assert cmd.can_keep?
    cmd.perform
    assert codespace.reload.keep?
  end

  test "can't keep if codespace is subject to a retention period policy" do
    user = create(:user)
    org = create(:codespaces_organization, plan: GitHub::Plan.business, admin: user)
    org_repo = create(:private_repository, owner: org)
    org.add_member(user)

    codespace = create(:codespace,
      owner: user,
      repository: org_repo,
      billable_owner: org,
      retention_period_minutes: 2.days.in_minutes.to_i)

    policy_group_org = create(:policy_group, owner: org, name: "all repos")
    create(:policy_group_membership,
      policy_group: policy_group_org,
      target: org)
    create(:policy_constraint,
      policy_group: policy_group_org,
      maximum_value: 10.days.in_minutes.to_i,
      allowed_values: nil,
      name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD)

    cmd = Codespaces::Keep.new(codespace)

    refute cmd.can_keep?
    cmd.perform
    refute codespace.reload.keep?
  end
end unless GitHub.enterprise?
