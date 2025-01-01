# typed: true
# frozen_string_literal: true

require "test_helper"

class GateBranchPolicyTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @repo = create(:repository)
    @env = create(:environment, repository: @repo)
    @gate = create(:gate, :with_branch_policy, environment: @env)
  end

  context "name validation" do
    test "invalid when the branch name is nil" do
      gate_branch_policy = build(:gate_branch_policy, gate: @gate, name: nil)

      refute_predicate gate_branch_policy, :valid?
    end
    test "invalid when the branch name is too long" do
      long_branch_name = "a" * 1025
      gate_branch_policy = build(:gate_branch_policy, gate: @gate, name: long_branch_name)

      refute_predicate gate_branch_policy, :valid?
    end

    test "valid for branches of 1024 bytes" do
      max_branch_name = "a" * 1024
      gate_branch_policy = build(:gate_branch_policy, gate: @gate, name: max_branch_name)

      assert_predicate gate_branch_policy, :valid?
    end

    test "valid when branch name contains slashes" do
      gate_branch_policy = build(:gate_branch_policy, gate: @gate, name: "users/monalisa")

      assert_predicate gate_branch_policy, :valid?
    end

    test "valid when branch name contains wildcards" do
      gate_branch_policy = build(:gate_branch_policy, gate: @gate, name: "users/monalisa/*")

      assert_predicate gate_branch_policy, :valid?
    end

    test "invalid if branch policy already exists" do
      existing_gate_branch_policy = create(:gate_branch_policy, gate: @gate, name: "sample_branch_policy2")
      duplicate_gate_branch_policy = build(:gate_branch_policy, gate: @gate, name: "sample_branch_policy2")
      refute_predicate duplicate_gate_branch_policy, :valid?
    end

    test "invalid if tag policy already exists" do
      existing_gate_branch_policy = create(:gate_branch_policy, gate: @gate, name: GateBranchPolicy::PROTECTED_TAG_PREFIX + "a_tag_policy")
      duplicate_gate_branch_policy = build(:gate_branch_policy, gate: @gate, name: GateBranchPolicy::PROTECTED_TAG_PREFIX + "a_tag_policy")
      refute_predicate duplicate_gate_branch_policy, :valid?
    end

    test "tag and branch policy with same name can coexist" do
      branch_policy = create(:gate_branch_policy, gate: @gate, name: "a_branch_policy")
      tag_policy = build(:gate_branch_policy, gate: @gate, name: GateBranchPolicy::PROTECTED_TAG_PREFIX + "a_branch_policy")
      assert_predicate tag_policy, :valid?
    end

    test "no exception if environment gets deleted" do
      env = create(:environment, repository: @repo)
      gate = create(:gate, :with_branch_policy, environment: env)
      gate_branch_policy = build(:gate_branch_policy, gate: gate, name: "users/monalisa")

      assert_predicate gate_branch_policy, :valid?

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob, BatchInactivateDeploymentsJob]) do
        env.destroy
      end

      assert_raises(ActiveRecord::RecordNotFound) { env.reload }
      assert_raises(ActiveRecord::RecordNotFound) { gate.reload }

      assert_nothing_raised do
        gate_branch_policy.destroy
      end
    end
  end

  test "supports emoji for name" do
    encoded_value = "we-❤️-emojis"
    encoded_value2 = "we-\xE2\x9D\xA4\xEF\xB8\x8F-emojis"
    encoded_value3 = "test-🧪"
    gate_branch_policy = create(:gate_branch_policy, gate: @gate, name: encoded_value)

    assert_multibyte_tracked_changes(gate_branch_policy, :name, encoded_value, encoded_value2, encoded_value3)
  end
end
