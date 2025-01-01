# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadRepositoryDispatchPayloadTest < GitHub::TestCase

  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org = create(:organization, admin: @org_admin, plan: "diamond")
    @org.save!
    @team = create(:team, organization: @org, permission: "admin")
    @team.add_member @org_admin

    @owner = create(:user, login: "jessicard", password: GitHub.default_password, plan: "large")

    @team.add_member @owner

    @repo = create(:private_repository, owner: @owner, name: "test-repository-trigger", description: "a repository", from_example: :repository_test_simple)
    @team.add_repository @repo, :pull

    example_repo_snapshot
  end

  test "payload contains repository hash" do
    event = Hook::Event::RepositoryDispatchEvent.new(repository_id: @repo.id,
            action: "sample.collected", actor_id: @owner.id,
            branch: @repo.default_branch)
    payload = Hook::Payload::RepositoryDispatchPayload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:simple_repository_hash, @repo)

    actual = v3[:repository]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  test "payload contains sender hash" do
    event = Hook::Event::RepositoryDispatchEvent.new(repository_id: @repo.id,
            action: "sample.collected", actor_id: @owner.id,
            branch: @repo.default_branch)
    payload = Hook::Payload::RepositoryDispatchPayload.new event
    v3 = payload.to_hash

    expected = Api::Serializer.serialize(:simple_user_hash, @owner)

    # puts "sender is #{v3[:sender].to_json}"
    actual = v3[:sender]
    expected.each do |key, value|
      assert_equal value, actual[key], "Unexpected value for :#{key}"
    end
  end

  test "payload contains action type" do
    event = Hook::Event::RepositoryDispatchEvent.new(
      repository_id: @repo.id,
      action: "created",
      user_action: "sample.collected",
      actor_id: @owner.id,
      branch: @repo.default_branch,
    )
    payload = Hook::Payload::RepositoryDispatchPayload.new event
    v3 = payload.to_hash
    assert_equal "sample.collected", v3[:action]
  end

  test "payload contains branch" do
    event = Hook::Event::RepositoryDispatchEvent.new(repository_id: @repo.id,
            action: "sample.collected", actor_id: @owner.id,
            branch: @repo.default_branch)
    payload = Hook::Payload::RepositoryDispatchPayload.new event
    v3 = payload.to_hash

    assert_equal @repo.default_branch, v3[:branch]
  end

  test "payload contains client_payload" do
    event = Hook::Event::RepositoryDispatchEvent.new(repository_id: @repo.id,
      action: "sample.collected", actor_id: @owner.id,
      branch: @repo.default_branch, client_payload: {
        sample_size: 1000,
      })
    payload = Hook::Payload::RepositoryDispatchPayload.new event
    v3 = payload.to_hash

    assert_equal 1000, v3[:client_payload][:sample_size]
  end
end
