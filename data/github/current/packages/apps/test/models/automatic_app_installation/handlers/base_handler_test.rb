# typed: true
# frozen_string_literal: true

require "test_helper"

class AutomaticAppInstallation::Handlers::HandlerTest < GitHub::TestCase

  class TestHandler < AutomaticAppInstallation::Handlers::BaseHandler
  end

  fixtures do
    @user = create(:user)
    @trigger = create(:integration_install_trigger)
  end

  test "validation is successful when the required arguments are supplied" do
    handler = TestHandler.new(install_triggers: [@trigger], originator: @user, actor: @user)
    result = handler.validate

    assert_predicate result, :success?
  end

  test "validation is unsuccessful when actor is not supplied" do
    handler = TestHandler.new(install_triggers: [@trigger], originator: @user, actor: nil)
    result = handler.validate

    refute_predicate result, :success?
    assert_equal :actor_not_supplied, result.reason
  end

  test "validation is unsuccessful when originator is not supplied" do
    handler = TestHandler.new(install_triggers: [@trigger], originator: nil, actor: @user)
    result = handler.validate

    refute_predicate result, :success?
    assert_equal :originator_not_supplied, result.reason
  end

  test "validation is unsuccessful when no install triggers are supplied" do
    handler = TestHandler.new(install_triggers: [], originator: @user, actor: @user)
    result = handler.validate

    refute_predicate result, :success?
    assert_equal :install_triggers_not_supplied, result.reason
  end

  test "validation is unsuccessful when one of the required arguments is not supplied" do
    handler = TestHandler.new(install_triggers: [@trigger], originator: @user, actor: nil)
    result = handler.validate

    refute_predicate result, :success?
    assert_equal :actor_not_supplied, result.reason
  end

  test "provides access to the install triggers, originator and actor" do
    handler = TestHandler.new(install_triggers: [], originator: nil, actor: nil)

    assert_equal [], handler.install_triggers
    assert_nil handler.originator
    assert_nil handler.actor
  end
end
