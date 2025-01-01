# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadWorkflowRunPayloadTest < GitHub::TestCase

  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner

    @repository   = create :repository, from_example: :simple
    @actions_app  = create :launch_integration

    sha = @repository.heads.find("master").target_oid
    @workflow = create(:workflow, repository: @repository, path: ".github/workflows/main.yml")
    check_suite = create(:check_suite_for_actions_app,
      status: :completed,
      conclusion: "success",
      head_sha: sha,
      repository: @repository,
      head_repository: @repository,
      event: "push",
      creator: @actions_app.bot,
      workflow_file_path: ".github/workflows/main.yml",
      completed_log_url: "https://logs.github.com/something",
      rerequestable: true,
      created_at: 3.weeks.ago
    )

    @workflow_run = check_suite.workflow_run
    @installation = make_integration_installation integration: @actions_app, target: @repository.owner, permissions: { "actions" => :write }
  end

  test "payload contains workflow_run hash" do
    event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "requested")
    payload = Hook::Payload::WorkflowRunPayload.new event

    v3 = payload.to_hash
    # puts "payload is #{v3.to_json}"
    expected = {
      id: @workflow_run.id,
      status: @workflow_run.status,
      event: @workflow_run.event,
      conclusion: @workflow_run.conclusion,
    }

    assert_equal "requested", v3[:action]
    actual = v3[:workflow_run]
    compare_maps(expected, actual)
  end

  test "payload contains sender hash" do
    event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "requested")
    payload = Hook::Payload::WorkflowRunPayload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:simple_user_hash, @actions_app.bot)

    actual = v3[:sender]
    compare_maps(expected, actual)
  end

  test "payload contains workflow hash" do
    event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "requested")
    payload = Hook::Payload::WorkflowRunPayload.new event
    v3 = payload.to_hash

    expected = {
      id: @workflow_run.workflow.id,
      name: @workflow_run.workflow.name,
      path: @workflow_run.workflow.path,
      state: @workflow_run.workflow.state,
    }

    actual = v3[:workflow]
    compare_maps(expected, actual)
  end

  test "payload contains repository hash" do
    event = Hook::Event::WorkflowRunEvent.new(run_id: @workflow_run.id, action: "requested")
    payload = Hook::Payload::WorkflowRunPayload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:simple_repository_hash, @repository)

    actual = v3[:repository]
    compare_maps(expected, actual)
  end

  def compare_maps(expected, actual)
    expected.each do |key, value|
      if value.nil?
        assert_nil actual[key], "Unexpected value for :#{key}"
      else
        assert_equal value, actual[key], "Unexpected value for :#{key}"
      end
    end
  end

end
