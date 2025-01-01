# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadTeamAddPayloadTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @team = create :team, organization: @org
    @repository = create :repository, owner: @org
  end

  setup do
    @event = Hook::Event::TeamAddEvent.new team_id: @team.id, repository_id: @repository.id
    @payload = Hook::Payload::TeamAddPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal @team.id, v3[:team][:id]
    assert_equal @team.name, v3[:team][:name]

    assert_equal @repository.id, v3[:repository][:id]
    assert_equal @repository.name, v3[:repository][:name]
  end

end
