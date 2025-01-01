# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkflowRunResourcesTest < GitHub::TestCase
  test "SUBJECT_TYPES" do
    expected_private_subject_types = %w(
      codespaces_prebuild
      reachability_analysis
    )

    assert_same_elements expected_private_subject_types, Actions::WorkflowRun::Resources.subject_types
  end

  test "WRITEONLY_SUBJECT_TYPES" do
    expected_writeonly_subject_types = %w(
      codespaces_prebuild
      reachability_analysis
    )

    assert_same_elements expected_writeonly_subject_types, Actions::WorkflowRun::Resources::WRITEONLY_SUBJECT_TYPES

    run = Actions::WorkflowRun.new
    expected_writeonly_subject_types.each do |subject_type|
      assert run.resources.respond_to?(subject_type.to_sym), "workflow run resources should include #{subject_type}"
    end
  end

  test "#workflow_run returns the parent run" do
    run = Actions::WorkflowRun.new
    assert_equal run, run.resources.workflow_run
  end

  test "ABILITY_TYPE_PREFIX" do
    assert_equal "WorkflowRun", Actions::WorkflowRun::Resources::ABILITY_TYPE_PREFIX
  end
end
