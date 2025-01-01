# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadRepositoryRulesetPayloadTest < GitHub::TestCase
  setup do
    @org = create(:organization, plan: "business_plus")
    @repo = create(:repository, owner: @org)
    @ruleset = create(:repository_ruleset, source: @repo)
    @org_ruleset = create(:repository_ruleset, source: @org)
  end

  test "includes repository ruleset" do
    event = Hook::Event::RepositoryRulesetEvent.new(action: :created, repository_ruleset_id: @ruleset.id, actor_id: @org.admins.first.id)

    payload = Hook::Payload::RepositoryRulesetPayload.new(event).to_hash

    refute_nil payload[:repository_ruleset]
    assert_equal Api::Serializer.serialize(:repository_ruleset_hash, @ruleset, request_source: @ruleset.source), payload[:repository_ruleset]
  end

  test "includes repo if repo ruleset" do
    event = Hook::Event::RepositoryRulesetEvent.new(action: :created, repository_ruleset_id: @ruleset.id, actor_id: @org.admins.first.id)

    payload = Hook::Payload::RepositoryRulesetPayload.new(event).to_hash

    refute_nil payload[:repository]
  end

  test "should include org if repo ruleset part of org" do
    event = Hook::Event::RepositoryRulesetEvent.new(action: :created, repository_ruleset_id: @ruleset.id, actor_id: @org.admins.first.id)

    payload = Hook::Payload::RepositoryRulesetPayload.new(event).to_hash

    refute_nil payload[:organization]
  end

  test "should not include org if repo ruleset not part of org" do
    user = create(:user)
    user_repo = create(:repository, owner: user)
    user_repo_ruleset = create(:repository_ruleset, source: user_repo)

    event = Hook::Event::RepositoryRulesetEvent.new(action: :created, repository_ruleset_id: user_repo_ruleset.id, actor_id: user.id)

    payload = Hook::Payload::RepositoryRulesetPayload.new(event).to_hash

    assert_nil payload[:organization]
  end

  test "should include org if org ruleset" do
    event = Hook::Event::RepositoryRulesetEvent.new(action: :created, repository_ruleset_id: @org_ruleset.id, actor_id: @org.admins.first.id)

    payload = Hook::Payload::RepositoryRulesetPayload.new(event).to_hash

    refute_nil payload[:organization]
  end

  test "should not include changes if not available" do
    event = Hook::Event::RepositoryRulesetEvent.new(action: :created, repository_ruleset_id: @org_ruleset.id, actor_id: @org.admins.first.id)

    payload = Hook::Payload::RepositoryRulesetPayload.new(event).to_hash

    assert_nil payload[:changes]
  end

  test "should include changes if available" do
    @ruleset.name = @ruleset.name + "-new"

    RepositoryRuleset.transaction do
      @ruleset.save!
    end

    event = Hook::Event::RepositoryRulesetEvent.new(action: :created, repository_ruleset_id: @ruleset.id, actor_id: @org.admins.first.id, changes: @ruleset.changes_payload)

    payload = Hook::Payload::RepositoryRulesetPayload.new(event).to_hash

    refute_nil payload[:changes]
    assert_equal event.changes, payload[:changes]
  end
end
