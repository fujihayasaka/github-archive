# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CacheEnvironmentDataJobTest < GitHub::TestCase
  test "it updates the environment data with provided hash when guid exists" do
    codespace = create(:codespace)
    Codespaces::CacheEnvironmentDataJob.perform_now("id" => codespace.guid)
    codespace.reload
    refute_nil codespace.environment_data
    assert_equal codespace.guid, codespace.environment_data.id
  end

  test "it does not break if there is no environment id in the hash" do
    codespace = create(:codespace)
    assert_nothing_raised { Codespaces::CacheEnvironmentDataJob.perform_now({}) }
  end

  test "it does not break if there is no codespace for the provided environment id" do
    codespace = create(:codespace)
    assert_nothing_raised { Codespaces::CacheEnvironmentDataJob.perform_now({ "id" => SecureRandom.uuid }) }
  end
end
