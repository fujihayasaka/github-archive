# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadWorkflowJobPayloadTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @github_app = create(:launch_integration)
  end

  setup do
    GitHub.stubs(:launch_github_app).returns(@github_app)
    GitHub.stubs(:actions_enabled?).returns(true)
    @workflow_check_suite = create(:check_suite_for_actions_app, name: "CI")
    @workflow_job_run = create(:check_run_for_actions_app, check_suite: @workflow_check_suite).workflow_job_run
    @workflow_job_run.update(label_data: %w[foo bar])
  end

  test "builds the correct payload when labels are present" do
    payload = build_workflow_job_run_payload(action: :queued).to_hash

    assert_equal :queued, payload[:action]
    refute_nil payload[:workflow_job]
    assert_equal @workflow_job_run.check_run_id, payload[:workflow_job][:id]
    assert_equal @workflow_job_run.workflow_run.workflow_name, payload[:workflow_job][:workflow_name]
    assert_equal @workflow_job_run.workflow_run.head_branch, payload[:workflow_job][:head_branch]
    assert_equal @workflow_job_run.check_run.status, payload[:workflow_job][:status]
    assert_equal @workflow_job_run.check_run.created_at, payload[:workflow_job][:created_at]
    assert_equal %w[bar foo], payload[:workflow_job][:labels].sort
  end

  test "builds the correct payload when no labels are present" do
    @workflow_job_run.update(label_data: nil)

    payload = build_workflow_job_run_payload(action: :queued).to_hash

    assert_equal [], payload[:workflow_job][:labels]
  end

  test "builds the correct payload when runner data is present" do
    @workflow_job_run.update(
      runner_id: 123,
      runner_name: "my cool runner",
      runner_group_id: 456,
      runner_group_name: "my cool runner group",
    )

    payload = build_workflow_job_run_payload(action: :queued).to_hash

    expected = {
      runner_id: 123,
      runner_name: "my cool runner",
      runner_group_id: 456,
      runner_group_name: "my cool runner group",
    }

    actual = payload[:workflow_job].slice(
      :runner_id,
      :runner_name,
      :runner_group_id,
      :runner_group_name,
    )

    assert_equal expected, actual
  end

  test "builds the correct payload when runner data is not present" do
    @workflow_job_run.update(
      runner_id: nil,
      runner_name: nil,
      runner_group_id: nil,
      runner_group_name: nil,
    )

    payload = build_workflow_job_run_payload(action: :queued).to_hash

    expected = {
      runner_id: nil,
      runner_name: nil,
      runner_group_id: nil,
      runner_group_name: nil,
    }

    actual = payload[:workflow_job].slice(
      :runner_id,
      :runner_name,
      :runner_group_id,
      :runner_group_name,
    )

    assert_equal expected, actual
  end

  test "doesn't include deployment information when the job does not have a deployment" do
    payload = build_workflow_job_run_payload(action: :queued).to_hash

    assert_equal :queued, payload[:action]
    refute_nil payload[:workflow_job]
    assert_nil payload[:deployment]
  end

  test "includes deployment information when the job has a deployment" do
    check_run = create(:check_run_for_actions_app)
    workflow_job_run = check_run.workflow_job_run
    deployment = create(:deployment, check_run: workflow_job_run.check_run)

    event = Hook::Event::WorkflowJobEvent.new(action: :queued, job_id: workflow_job_run.id)
    payload = Hook::Payload::WorkflowJobPayload.new(event).to_hash

    assert_equal :queued, payload[:action]
    refute_nil payload[:workflow_job]
    refute_nil payload[:deployment]
  end

  test "logs serializer exceptions and raises" do
    exception = NoMethodError.new("you're missing something")
    Api::Serializer.stubs(:serialize).raises(exception).once

    GitHub.logger.expects(:error).with(anything, has_entries({
      "code.namespace" => "Hook::Payload::WorkflowJobPayload",
      "code.function" => "to_payload_hash",
      "gh.check_run.id" =>  @workflow_job_run.check_run_id,
      "gh.repo.id" =>  @workflow_job_run.repository_id,
      "gh.workflow_run.id" =>  @workflow_job_run.workflow_run_id,
      "gh.workflow_job_run.id" => @workflow_job_run.id,
      "gh.webhook.action" => :queued,
      :exception => exception
    })).once

    assert_raises(NoMethodError) do
      build_workflow_job_run_payload(action: :queued).to_hash
    end
  end

  def build_workflow_job_run_payload(attrs = {})
    default_attrs = {
      action: :queued,
      job_id: @workflow_job_run.id,
    }
    event = Hook::Event::WorkflowJobEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::WorkflowJobPayload.new(event)
  end
end
