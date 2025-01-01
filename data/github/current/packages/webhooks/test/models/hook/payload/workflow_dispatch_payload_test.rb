# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadWorkflowDispatchPayloadTest < GitHub::TestCase

  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org = create(:organization, admin: @org_admin, plan: "diamond")
    @org.save!
    @team = create(:team, organization: @org, permission: "admin")
    @team.add_member @org_admin

    @owner = create(:user)

    @team.add_member @owner

    @repo = create(:private_repository, owner: @owner, name: "test repo", description: "test", from_example: :repository_test_simple)
    @team.add_repository @repo, :pull

    example_repo_snapshot
  end

  test "payload contains repository hash" do
    event = Hook::Event::WorkflowDispatchEvent.new(repository_id: @repo.id,
            actor_id: @owner.id, workflow: ".github/workflows/test.yaml",
            ref: @repo.default_branch_ref.qualified_name)
    payload = Hook::Payload::WorkflowDispatchPayload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:simple_repository_hash, @repo)

    actual = v3[:repository]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  test "payload contains sender hash" do
    event = Hook::Event::WorkflowDispatchEvent.new(repository_id: @repo.id,
            actor_id: @owner.id, workflow: ".github/workflows/test.yaml",
            ref: @repo.default_branch_ref.qualified_name)
    payload = Hook::Payload::WorkflowDispatchPayload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:simple_user_hash, @owner)

    # puts "sender is #{v3[:sender].to_json}"
    actual = v3[:sender]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  test "payload contains branch" do
    event = Hook::Event::WorkflowDispatchEvent.new(repository_id: @repo.id,
            actor_id: @owner.id, workflow: ".github/workflows/test.yaml",
            ref: @repo.default_branch_ref.qualified_name)
    payload = Hook::Payload::WorkflowDispatchPayload.new event
    v3 = payload.to_hash

    assert_equal @repo.default_branch_ref.qualified_name, v3[:ref]
  end

  test "payload contains workflow" do
    event = Hook::Event::WorkflowDispatchEvent.new(repository_id: @repo.id,
      actor_id: @owner.id, workflow: ".github/workflows/test.yaml",
      ref: @repo.default_branch_ref.qualified_name)
    payload = Hook::Payload::WorkflowDispatchPayload.new event
    v3 = payload.to_hash

    assert_equal ".github/workflows/test.yaml", v3[:workflow]
  end

  test "payload does not contain inputs if not specified" do
    event = Hook::Event::WorkflowDispatchEvent.new(repository_id: @repo.id,
      actor_id: @owner.id, workflow: ".github/workflows/test.yaml",
      ref: @repo.default_branch_ref.qualified_name)
    payload = Hook::Payload::WorkflowDispatchPayload.new event
    v3 = payload.to_hash

    assert_nil v3[:inputs]
  end

  test "payload contains inputs if specified" do
    event = Hook::Event::WorkflowDispatchEvent.new(repository_id: @repo.id,
      actor_id: @owner.id, workflow: ".github/workflows/test.yaml",
      ref: @repo.default_branch_ref.qualified_name, inputs: { "name": "monalisa", "num": "23" })
    payload = Hook::Payload::WorkflowDispatchPayload.new event
    v3 = payload.to_hash

    assert_equal ({ "name": "monalisa", "num": "23" }), v3[:inputs]
  end
end
