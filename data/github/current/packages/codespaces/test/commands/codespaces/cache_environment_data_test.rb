# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class CacheEnvironmentDataTest < GitHub::TestCase
    test "it updates the environment data with provided hash when guid exists" do
      codespace = create(:codespace, environment_data: nil)
      Codespaces::CacheEnvironmentDataJob.perform_now("id" => codespace.guid, "state" => Codespaces::Vscs::State::QUEUED)
      refute_nil codespace.reload.environment_data
      assert_equal Codespaces::Vscs::State::QUEUED, codespace.environment_data.state
    end

    test "it does not break if there is no environment id in the hash" do
      assert_nothing_raised { Codespaces::CacheEnvironmentDataJob.perform_now({ "state" => Codespaces::Vscs::State::QUEUED }) }
    end

    test "it does not break if there is no codespace for the provided environment id" do
      assert_nothing_raised { Codespaces::CacheEnvironmentDataJob.perform_now({ "id" => SecureRandom.uuid, "state" => Codespaces::Vscs::State::QUEUED }) }
    end

    test "it reports an error if the codespace state is null" do
      Codespaces::ErrorReporter.expects(:report).with { |error, _| error.kind_of?(Codespaces::NullStateCodespaceError) }
      Codespaces::CacheEnvironmentDataJob.perform_now({ "id" => SecureRandom.uuid })
    end
  end
end
