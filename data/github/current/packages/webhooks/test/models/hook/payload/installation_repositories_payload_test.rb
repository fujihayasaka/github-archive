# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadInstallationRepositoriesPayloadTest < GitHub::TestCase
  fixtures do
    @owner  = create(:user, login: "owner")

    @repo_a = create(:repository, owner: @owner)
    @repo_b = create(:repository, owner: @owner)

    @installation = make_integration_installation(repository: @repo_a)
  end

  context "v3" do
    test "added" do
      @repo_b = create(:repository, owner: @owner)

      options = {
        action:             :added,
        actor_id:           @owner.id,
        installation_id:    @installation.id,
        repositories_added: [@repo_b.id],
      }

      @event   = Hook::Event::InstallationRepositoriesEvent.new(options)
      @payload = Hook::Payload::InstallationRepositoriesPayload.new(@event)

      v3 = @payload.to_hash

      assert_equal :added, v3[:action]

      assert_equal @owner.login, v3[:sender][:login]
      assert_equal @owner.login, v3[:installation][:account][:login]

      assert_equal @repo_b.id,        v3[:repositories_added][0][:id]
      assert_equal @repo_b.name,      v3[:repositories_added][0][:name]
      assert_equal @repo_b.full_name, v3[:repositories_added][0][:full_name]
      assert_equal @repo_b.private?,  v3[:repositories_added][0][:private]

      assert v3.key?(:requester), "expected requester_id"
      assert_nil v3[:requester]
    end

    test "added via a request" do
      @repo_b    = create(:repository, owner: @owner)
      @requester = create(:user)

      options = {
        action:             :added,
        actor_id:           @owner.id,
        installation_id:    @installation.id,
        repositories_added: [@repo_b.id],
        requester_id:       @requester.id,
      }

      @event   = Hook::Event::InstallationRepositoriesEvent.new(options)
      @payload = Hook::Payload::InstallationRepositoriesPayload.new(@event)

      v3 = @payload.to_hash

      assert_equal :added, v3[:action]

      assert_equal @owner.login, v3[:sender][:login]
      assert_equal @owner.login, v3[:installation][:account][:login]

      assert_equal @repo_b.id,        v3[:repositories_added][0][:id]
      assert_equal @repo_b.name,      v3[:repositories_added][0][:name]
      assert_equal @repo_b.full_name, v3[:repositories_added][0][:full_name]
      assert_equal @repo_b.private?,  v3[:repositories_added][0][:private]

      assert_equal @requester.login, v3[:requester][:login]
    end

    test "removed" do
      options = {
        action:               :removed,
        actor_id:             @owner.id,
        installation_id:      @installation.id,
        repositories_removed: [@repo_a.id],
      }

      @event   = Hook::Event::InstallationRepositoriesEvent.new(options)
      @payload = Hook::Payload::InstallationRepositoriesPayload.new(@event)

      v3 = @payload.to_hash

      assert_equal :removed, v3[:action]

      assert_equal @owner.login, v3[:sender][:login]
      assert_equal @owner.login, v3[:installation][:account][:login]

      assert_equal @repo_a.id,        v3[:repositories_removed][0][:id]
      assert_equal @repo_a.name,      v3[:repositories_removed][0][:name]
      assert_equal @repo_a.full_name, v3[:repositories_removed][0][:full_name]
      assert_equal @repo_a.private?,  v3[:repositories_removed][0][:private]
    end
  end
end
