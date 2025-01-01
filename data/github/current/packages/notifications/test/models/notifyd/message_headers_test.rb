# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class MessageHeadersTest < GitHub::TestCase
    test "#to_h returns a hash with semantic keys" do
      expected = {
        "notifyd-message-published-to" => "test",
        "notifyd-message-producer" => "github-test",
        "other" => "hi",
        "X-GitHub-Tenant" => "avocado",
      }

      headers = Notifyd::MessageHeaders.new
      headers[:published_to] = "test"
      headers[:producer] = "github-test"
      headers[:other] = :hi
      headers[:tenant_slug] = "avocado"
      headers[:nope] = nil # nil values are ignored

      assert_equal expected, headers.to_h
    end

    test "#with_telemetry sets header with telemetry values" do
      expected = {
        "gh-request-id" => "abc123",
        "traceparent" => "00-80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1-00"
      }

      headers = Notifyd::MessageHeaders.new.with_telemetry(
        context: { request_id: "abc123" },
        context_propagation_map: { traceparent: "00-80f198ee56343ba864fe8b2a57d3eff7-e457b5a2e4d86bd1-00" },
      )

      assert_equal expected, headers.to_h
    end

    test "#with_github_env sets header with GitHub env values" do
      expected = {
        "gh-env" => "test",
        "gh-dynamic-lab-name" => "testing"
      }

      github = Struct.new(:deployed_to, :dynamic_lab_name, :dynamic_lab?)
        .new("test", "testing", true)

      headers = Notifyd::MessageHeaders.new.with_github_env(github: github)

      assert_equal expected, headers.to_h
    end

    test "#with_tenant_context sets header with current tenant values" do
      expected = {
        "X-GitHub-Tenant" => "avocado",
        "X-GitHub-Tenant-ID" => "123",
      }

      tenant = Struct.new(:slug, :id).new("avocado", "123")
      context = Struct.new(:get).new(tenant)

      headers = Notifyd::MessageHeaders.new.with_tenant_context(current_tenant: context)

      assert_equal expected, headers.to_h
    end
  end
end
