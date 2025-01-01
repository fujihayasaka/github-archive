# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::BackfillEnvironmentDataJobTest < GitHub::TestCase
  test "it updates the environment data with fetch_environment results" do
    codespace = create(:codespace)
    FakeVSOServer.reset!
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::SHUTDOWN }
    Codespaces::BackfillEnvironmentDataJob.perform_now(codespace: codespace)
    refute_nil codespace.environment_data
    assert_equal Codespaces::Vscs::State::SHUTDOWN, codespace.environment_data.state
  end

  test "it doesn't break if a codespace has no guid" do
    codespace = create(:codespace, :unprovisioned)
    assert_nothing_raised { Codespaces::BackfillEnvironmentDataJob.perform_now(codespace: codespace) }
  end
end
