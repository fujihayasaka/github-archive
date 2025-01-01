# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadDeploymentPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user
    @deployment = create :deployment, repository: @repo, creator: @user
  end

  setup do
    @event = Hook::Event::DeploymentEvent.new deployment_id: @deployment.id
    @payload = Hook::Payload::DeploymentPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal @deployment.id, v3[:deployment][:id]
    assert_equal @deployment.sha, v3[:deployment][:sha]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
    assert_equal [:action, :deployment, :repository, :sender, :workflow, :workflow_run], v3.keys.sort
  end
end
