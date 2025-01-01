# typed: true
# frozen_string_literal: true

require "test_helper"

class ResiliencyResponseTest < GitHub::TestCase
  test "sets value to default_value if no block given" do
    response = Resiliency::Response.new("custom")
    assert_equal "custom", response.value
  end

  test "sets success to true if no block given" do
    response = Resiliency::Response.new("custom")
    assert_equal true, response.success?
  end

  test "sets value to default_value if unavailable exception is raised" do
    response = Resiliency::Response.new { raise Resiliency::Response::UnavailableExceptions.first }
    assert_nil response.value
  end

  test "sets value to default_value if Resilient::Trilogy::CircuitOpenError is raised" do
    response = Resiliency::Response.new { raise Resilient::Trilogy::CircuitOpenError.new(:test) }
    assert_nil response.value
  end

  test "sets value to custom default_value if unavailable exception is raised" do
    response = Resiliency::Response.new("custom") { raise Resiliency::Response::UnavailableExceptions.first }
    assert_equal "custom", response.value
  end

  test "sets success to true if nothing raised" do
    response = Resiliency::Response.new { "all good" }
    assert_equal true, response.success?
  end

  test "sets success to false if unavailable exception is raised" do
    response = Resiliency::Response.new { raise Resiliency::Response::UnavailableExceptions.first }
    assert_equal false, response.success?
  end

  test "sets success to false if exception raised is not one of the unvailable ones" do
    assert_raises RuntimeError do
      response = Resiliency::Response.new { raise "boom" }
      assert_equal false, response.success?
    end
  end

  test "raises exception if not one of the unavailable ones" do
    assert_raises RuntimeError do
      Resiliency::Response.new { raise "boom" }
    end
  end

  test "emits datadog stats" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

    Resiliency::Response.new { raise ActiveRecord::ConnectionNotEstablished }

    stat = GitHub.dogstats.increments("request.resilience.caught_errors").first

    assert_includes stat.tags, "root_error:ActiveRecord::ConnectionNotEstablished"
    assert_includes stat.tags, "matched_error_type:ActiveRecord::ConnectionNotEstablished"
    assert_includes stat.tags, "resilience_method:Resiliency::Response"
    assert_includes stat.tags, "view_template:nil"
    assert_includes stat.tags, "controller:unknown"
    assert_includes stat.tags, "action:unknown"
    assert_includes stat.tags, "catalog_service:unknown"
    assert_includes stat.tags, "database_cluster:unknown"
    assert_includes stat.tags, "database_connection_role:unknown"
  end
end
