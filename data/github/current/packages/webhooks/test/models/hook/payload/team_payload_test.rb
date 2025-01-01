# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadTeamPayloadTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, admin: @owner)
    @repo = create :repository, owner: @org
    @team = create :team, organization: @org
    @team.add_repository @repo, :push
  end

  [:created, :deleted].each do |action|
    context "when the Team is #{action}" do
      test "v3" do
        payload = build_team_payload(action: action)
        v3 = payload.to_hash

        assert_equal action, v3[:action]
        assert_equal @team.id, v3[:team][:id]
        assert_equal @org.id, v3[:organization][:id]
        assert_equal @owner.id, v3[:sender][:id]
        assert_equal @owner.login, v3[:sender][:login]
      end
    end
  end

  context "when a Teams's attributes are updated" do
    test "v3" do
      changes = {
        old_description: "Changed Description",
        old_name: "Changed Title",
        old_privacy: 0,
      }
      payload = build_team_payload(action: :edited, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_includes v3, :changes
      assert_equal @team.id, v3[:team][:id]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @owner.id, v3[:sender][:id]
      assert_equal @owner.login, v3[:sender][:login]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal true, v3[:repository][:permissions][:pull]
    end
  end

  context "when a Teams's permissions change" do
    test "v3" do
      changes = {
        old_permissions: { push: false, pull: true, admin: false },
      }
      payload = build_team_payload(action: :edited, repo_id: @repo.id, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_includes v3, :changes
      assert_equal @team.id, v3[:team][:id]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @owner.id, v3[:sender][:id]
      assert_equal @owner.login, v3[:sender][:login]

      expected_changes_payload = {
        repository: {
          permissions: {
            from: {
              push: false,
              pull: true,
              admin: false,
            },
          },
        },
      }

      assert_equal expected_changes_payload, v3[:changes]
    end
  end

  context "when a Team is added to a repository" do
    test "v3" do
      payload = build_team_payload(action: :added_to_repository, repo_id: @repo.id)
      v3 = payload.to_hash

      assert_equal :added_to_repository, v3[:action]
      assert_equal @team.id, v3[:team][:id]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @owner.id, v3[:sender][:id]
      assert_equal @owner.login, v3[:sender][:login]
      assert_equal true, v3[:repository][:permissions][:push]
    end
  end

  context "when a Team is removed from a repository" do
    test "v3" do
      @team.remove_repository_directly(@repo)
      payload = build_team_payload(action: :removed_from_repository, repo_id: @repo.id)
      v3 = payload.to_hash

      assert_equal :removed_from_repository, v3[:action]
      assert_equal @team.id, v3[:team][:id]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @owner.id, v3[:sender][:id]
      assert_equal @owner.login, v3[:sender][:login]
      assert_equal false, v3[:repository][:permissions][:push]
    end
  end

  [:created, :deleted, :edited, :added_to_repository, :removed_from_repository].each do |action|
    test "custom properties are part of the payload (#{action})" do
      env_definition = create :custom_property_definition, source: @org, property_name: "env"
      create :custom_property_definition, source: @org, property_name: "language", required: true, default_value: "ruby"
      create :custom_property_value, definition: env_definition, target: @repo, value: "prod"

      @team.remove_repository_directly(@repo) if action == :removed_from_repository
      changes = if action == :edited
        {
          old_description: "Changed Description",
          old_name: "Changed Title",
          old_privacy: 0,
        }
      else
        nil
      end

      payload = build_team_payload(action: :removed_from_repository, repo_id: @repo.id, changes: changes)

      v3 = payload.to_hash
      repository_data = v3[:repository]

      assert_equal @repo.id, repository_data[:id]
      assert_equal repository_data[:custom_properties], { env: "prod", language: "ruby" }
    end
  end

  def build_team_payload(attrs = {})
    default_attrs = {
      team_id: @team.id,
      actor_id: @owner.id,
      repo_id: @repo.id,
    }

    event = Hook::Event::TeamEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::TeamPayload.new(event)
  end
end
