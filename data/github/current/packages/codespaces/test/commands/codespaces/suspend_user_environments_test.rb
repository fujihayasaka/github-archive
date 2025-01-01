# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::SuspendUserEnvironmentsTest < GitHub::TestCase
  class MockFailbot
    def push(payload = {})
      payloads << payload
      yield if block_given?
    end

    def payloads
      @payloads ||= []
    end
  end

  setup do
    @user = create(:user)
    @codespaces = create_list(:codespace, 3, owner: @user)
    @failbot = MockFailbot.new
    @reporter = Codespaces::ErrorReporter.new(reporter: @failbot)
    @options = {
      error_reporter: @reporter,
    }
    FakeVSOServer.reset!
    FakeVSOServer.environments.concat(@codespaces.map { |codespace| { id: codespace.guid }.with_indifferent_access })
  end

  test "pushes each codespace context" do
    Codespaces::SuspendUserEnvironments.new(@user, **@options).call
    assert_equal @failbot.payloads.count, 3
  end

  test "attempts to shutdown a user's provisioned codespaces" do
    assert_empty FakeVSOServer.environments_shutdown
    Codespaces::SuspendUserEnvironments.new(@user, **@options).call
    assert_equal FakeVSOServer.environments_shutdown.pluck(:id), @codespaces.map(&:guid)
  end

  test "allows a different scope to be provided for which codespaces to suspend" do
    Codespaces::SuspendUserEnvironments.new(
      @user,
      **@options.merge(scope: @user.codespaces.none)
    ).call
    assert_equal FakeVSOServer.environments_shutdown.count, 0
  end
end
