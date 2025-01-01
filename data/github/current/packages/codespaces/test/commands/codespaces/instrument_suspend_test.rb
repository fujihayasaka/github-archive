# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesInstrumentSuspendTest < GitHub::TestCase
  setup_once do
    enable_cache_storage
  end

  teardown_once do
    disable_cache_storage
  end

  setup do
    reset_cache
    @actor = create(:user)
    @codespace = create(:codespace)
  end

  test "only instruments once when called multiple times" do
    events = subscribe "codespaces.suspend_environment"
    Codespaces::InstrumentSuspend.call(codespace: @codespace)
    Codespaces::InstrumentSuspend.call(codespace: @codespace)
    assert_equal events.length, 1
  end
end
