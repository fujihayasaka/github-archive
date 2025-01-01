# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadRepositoryPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create :organization, admin: @user
    @repo = create :repository, owner: @org
  end

  setup do
    @event = Hook::Event::RepositoryEvent.new action: :created, repository_id: @repo.id, actor_id: @user.id
    @payload = Hook::Payload::RepositoryPayload.new @event
    @transfer_from_user_event = Hook::Event::RepositoryEvent.new(action: :transferred,
                                                                 repository_id: @repo.id,
                                                                 actor_id: @user.id,
                                                                 changes: { old_user_id: @user.id, owner_was_org: false })
    @transfer_from_org_event = Hook::Event::RepositoryEvent.new(action: :transferred,
                                                                repository_id: @repo.id,
                                                                actor_id: @user.id,
                                                                changes: { old_user_id: @org.id, owner_was_org: true })
    @renamed_event = Hook::Event::RepositoryEvent.new(action: :renamed,
                                                      repository_id: @repo.id,
                                                      actor_id: @user.id,
                                                      changes: { old_name: "foo" })
    @renamed_payload = Hook::Payload::RepositoryPayload.new(@renamed_event)
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal :created, v3[:action]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
  end

  context "when changes present on repository transferred event" do
    context "and source was an org" do
      test "includes changes in the final payload" do
        v3 = Hook::Payload::RepositoryPayload.new(@transfer_from_org_event).to_hash
        expected_changes = {
          from: {
            organization: Api::Serializer.serialize(:organization_hash, @org),
          },
        }

        assert_equal :transferred, v3[:action]
        assert_equal expected_changes, v3.dig(:changes, :owner)
      end
    end

    context "and source was a user" do
      test "includes changes in the final payload" do
        v3 = Hook::Payload::RepositoryPayload.new(@transfer_from_user_event).to_hash
        expected_changes = {
          from: {
            user: Api::Serializer.serialize(:user_hash, @user),
          },
        }

        assert_equal :transferred, v3[:action]
        assert_equal expected_changes, v3.dig(:changes, :owner)
      end
    end
  end

  context "when changes present on repository renamed event" do
    test "includes changes in the final payload" do
      v3 = @renamed_payload.to_hash
      expected_changes = { name: { from: "foo" } }

      assert_equal :renamed, v3[:action]
      assert_equal expected_changes, v3.dig(:changes, :repository)
    end
  end

  context "payload for edited event" do
    test "includes changes in the final payload" do
      event = Hook::Event::RepositoryEvent.new action: :edited, repository_id: @repo.id, actor_id: @user.id, changes: {
        homepage: "http://example.com",
        old_homepage: "http://old.example.com",
      }

      payload = Hook::Payload::RepositoryPayload.new(event)

      expected = {
        homepage: {
          from: "http://old.example.com",
        },
      }

      assert_equal expected, payload.to_hash.fetch(:changes)
    end
  end

end
