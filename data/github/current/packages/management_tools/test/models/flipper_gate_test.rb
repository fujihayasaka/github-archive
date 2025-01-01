# typed: true
# frozen_string_literal: true

require "test_helper"

class FlipperGateTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "jane-doe")
  end

  test "finding an actor" do
    gate = FlipperGate.new(name: "actor", value: "User:#{@user.id}")
    assert_equal @user, gate.actor
  end

end
