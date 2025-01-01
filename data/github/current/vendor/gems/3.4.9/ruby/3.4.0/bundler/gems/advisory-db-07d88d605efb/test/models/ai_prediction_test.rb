# frozen_string_literal: true

require "test_helper"

class AiPredictionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @prediction = create(:ai_prediction_gpt4o)
  end

  test "prompt includes only supported ecosystem and not 'Other'" do
    refute_includes @prediction.prompt, "Other"
    assert_includes @prediction.prompt, "GitHub Actions"
    assert_includes @prediction.prompt, "Composer"
    assert_includes @prediction.prompt, "Erlang"
    assert_includes @prediction.prompt, "Go"
    assert_includes @prediction.prompt, "Maven"
    assert_includes @prediction.prompt, "npm"
    assert_includes @prediction.prompt, "NuGet"
    assert_includes @prediction.prompt, "pip"
    assert_includes @prediction.prompt, "Pub.dev"
    assert_includes @prediction.prompt, "RubyGems"
    assert_includes @prediction.prompt, "Rust"
    assert_includes @prediction.prompt, "Swift"
  end

  test "process raw predicted ecosystem to save only supported ecosystems; if containing hallucinated values, defaults to 'Other'" do
    assert_equal @prediction.process_ecosystem_prediction("Maven"), "maven"
    assert_equal @prediction.process_ecosystem_prediction("Other"), "other"
    assert_equal @prediction.process_ecosystem_prediction("Whatever"), "other"
  end

  test "process raw predicted package to save only supported package formats; save empty string if illegal format" do
    assert_equal @prediction.process_package_prediction("Maven", "asadguasga"), ""
    assert_equal @prediction.process_package_prediction("Maven", "org.opennms:opennms-webapp"), "org.opennms:opennms-webapp"
    assert_equal @prediction.process_package_prediction("Composer", "asaisjas"), ""
    assert_equal @prediction.process_package_prediction("Composer", "miniorange/miniorange-saml"), "miniorange/miniorange-saml"
    assert_equal @prediction.process_package_prediction("Rust", "abc/def"), ""
    assert_equal @prediction.process_package_prediction("Rust", "abc_de-f"), "abc_de-f"
  end

  test "defaults decision to a pending state" do
    assert_equal "pending", @prediction.curator_decision
  end

  test "can mark the decision as rejected" do
    assert_equal "pending", @prediction.curator_decision
    assert_nil @prediction.decided_at
    @prediction.reject!
    assert_equal "rejected", @prediction.curator_decision
    refute_nil @prediction.decided_at
  end

  test "can mark the decision as accepted" do
    assert_equal "pending", @prediction.curator_decision
    assert_nil @prediction.decided_at
    @prediction.accept!
    assert_equal "accepted", @prediction.curator_decision
    refute_nil @prediction.decided_at
  end
end
