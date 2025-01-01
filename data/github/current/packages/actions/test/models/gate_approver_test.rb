# typed: true
# frozen_string_literal: true

require "test_helper"

class GateApproverTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @team = create(:team, organization: @org, privacy: :closed)
    @repo = create(:private_repository, owner: @org)
    @repo.add_team(@team, action: :write)
    @env = create(:environment, repository: @repo)
    @gate = create(:gate, type: :manual_approval, environment: @env)
  end

  test "is invalid if user approver is not a repo collaborator" do
    random_user = create(:user)
    approver = @gate.gate_approvers.new(repository: @env.repository, approver: random_user)
    refute approver.valid?
    assert_includes approver.errors.messages[:approver], "must be a collaborator"
  end

  test "is valid if user approver is a repo collaborator" do
    approver = @gate.gate_approvers.new(repository: @env.repository, approver: @owner)
    assert approver.valid?
  end

  test "is invalid if team approver is not a repo collaborator" do
    random_team = create(:team)
    approver = @gate.gate_approvers.new(repository: @env.repository, approver: random_team)
    refute approver.valid?
    assert_includes approver.errors.messages[:approver], "must be a collaborator"
  end

  test "is valid if team approver is a repo collaborator" do
    approver = @gate.gate_approvers.new(repository: @env.repository, approver: @team)
    assert approver.valid?
  end

  test "validates uniqueness of approver per gate" do
    @gate.gate_approvers.create!(repository: @env.repository, approver: @owner)
    approver = @gate.gate_approvers.create(repository: @env.repository, approver: @owner)
    refute approver.valid?
    assert_includes approver.errors.messages[:approver_id], "is already an approver"
  end
end
