# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class HookPayloadGollumPayloadTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    Spokesd.enable_spokesd
    @user = create(:user, login: "acme")
    @repo = create :repository, owner: @user, name: "widgets"
    @wiki = @repo.unsullied_wiki
    @updates = [
      { action: :edited,  page_name: "home",  sha: "e1b2d813b10050b74a2accdaba10965e03152a1e" },
    ]
  end

  setup do
    Spokesd.enable_spokesd
    example_repo :wiki, @wiki
    @event = Hook::Event::GollumEvent.new actor_id: @user.id, repository_id: @repo.id, updates: @updates
    @payload = Hook::Payload::GollumPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal 1, v3[:pages].count
    assert_equal "home", v3[:pages][0][:page_name]
    assert_equal "home", v3[:pages][0][:title]
    assert_equal :edited, v3[:pages][0][:action]
    assert_equal "e1b2d813b10050b74a2accdaba10965e03152a1e", v3[:pages][0][:sha]
    assert_equal "https://github.com/acme/widgets/wiki/home", v3[:pages][0][:html_url]

    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @repo.name, v3[:repository][:name]
    assert_equal @user.id, v3[:sender][:id]
    assert_equal @user.login, v3[:sender][:login]
  end
end
