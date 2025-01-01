# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class HooksTest < Api::SerializerTestCase
  extend T::Helpers

  fixtures do
    user = create :user, login: "defunkt"
    repo = create :repository, name: "dotfiles", owner: user
    org = create(:organization, admin: user, plan: "bronze", login: "stark-industries")
    app = create(:integration)
    config = { "url" => "http://example.com" }
    t = Time.parse("2019/01/01 10:00:00 UTC")
    Timecop.freeze(t) do
      @org_hook = create :hook, :org,
        installation_target: org,
        config: config,
        events: %w(public)

      @repo_hook = create :hook, :web, installation_target: repo, config: config
      @app_hook = create :hook, installation_target: app, events: %w(public), config: config
    end
  end

  context "#global_hook_hash" do
    context "for an org hook" do
      test "payload is valid" do
        output = T.unsafe(self).global_hook(@org_hook)
        assert output.key?("id")
        assert output.key?("name")
        assert output.key?("active")
        assert output.key?("events")
      end

      test "payload has right values" do
        output = T.unsafe(self).global_hook(@org_hook)

        expected_payload = {
          "type" => "User",
          "id" => @org_hook.id,
          "name" => "web",
          "active" => true,
          "events" => ["public"],
          "config" => {
            "url" => "http://example.com",
            "insecure_ssl" => "0",
            "content_type" => "form",
          },
          "updated_at" => "2019-01-01T10:00:00Z",
          "created_at" => "2019-01-01T10:00:00Z",
          "url" => "#{GitHub.api_url}/admin/hooks/#{@org_hook.id}",
          "ping_url" => "#{GitHub.api_url}/admin/hooks/#{@org_hook.id}/pings",
        }

        assert_equal expected_payload, output
      end
    end

    test "is nil when hook is missing" do
      assert_nil T.unsafe(self).global_hook(nil)
    end

    context "for a repo hook" do
      test "payload is valid" do
        output = T.unsafe(self).global_hook(@repo_hook)
        assert output.key?("id")
        assert output.key?("name")
        assert output.key?("active")
        assert output.key?("events")
      end

      test "payload has right values" do
        output = T.unsafe(self).global_hook(@repo_hook)

        expected_payload = {
          "type" => "Repository",
          "id" => @repo_hook.id,
          "name" => "web",
          "active" => true,
          "events" => ["push"],
          "config" => {
            "url" => "http://example.com",
            "insecure_ssl" => "0",
            "content_type" => "form",
          },
          "updated_at" => "2019-01-01T10:00:00Z",
          "created_at" => "2019-01-01T10:00:00Z",
          "url" => "#{GitHub.api_url}/admin/hooks/#{@repo_hook.id}",
          "ping_url" => "#{GitHub.api_url}/admin/hooks/#{@repo_hook.id}/pings",
        }

        assert_equal expected_payload, output
      end
    end
  end

  context "#repo_hook_hash" do
    test "payload is valid" do
      output = T.unsafe(self).repo_hook(@repo_hook)

      expected_payload = {
        "type" => "Repository",
        "id" => @repo_hook.id,
        "name" => "web",
        "active" => true,
        "events" => ["push"],
        "config" => {
          "url" => "http://example.com",
          "insecure_ssl" => "0",
          "content_type" => "form",
        },
        "updated_at" => "2019-01-01T10:00:00Z",
        "created_at" => "2019-01-01T10:00:00Z",
        "url" => "#{GitHub.api_url}/repos/defunkt/dotfiles/hooks/#{@repo_hook.id}",
        "test_url" => "#{GitHub.api_url}/repos/defunkt/dotfiles/hooks/#{@repo_hook.id}/test",
        "ping_url" => "#{GitHub.api_url}/repos/defunkt/dotfiles/hooks/#{@repo_hook.id}/pings",
        "deliveries_url" => "#{GitHub.api_url}/repos/defunkt/dotfiles/hooks/#{@repo_hook.id}/deliveries",
        "last_response" => { "code" => nil, "status" => "unused", "message" => nil },
      }

      assert_equal expected_payload, output
    end

    test "returns nil when hook is missing" do
      output = T.unsafe(self).repo_hook(nil)
      assert_nil output
    end

    test "returns information about the last response if one exists" do
      @repo_hook.last_status = 504
      output = T.unsafe(self).repo_hook(@repo_hook)

      expected_last_response_hash = {
        "code"    => 504,
        "status"  => "timeout",
        "message" => nil,
      }

      assert_equal expected_last_response_hash, output.fetch("last_response")
    end
  end

  context "#org_hook_hash" do
    test "payload is valid" do
      output = T.unsafe(self).org_hook(@org_hook)
      assert output.key?("id")
      assert output.key?("name")
      assert output.key?("active")
      assert output.key?("events")
    end

    test "is nil when hook is missing" do
      assert_nil T.unsafe(self).org_hook(nil)
    end

    test "payload has right values" do
      output = T.unsafe(self).org_hook(@org_hook)

      expected_payload = {
        "type" => "Organization",
        "id" => @org_hook.id,
        "name" => "web",
        "active" => true,
        "events" => ["public"],
        "config" => {
          "url" => "http://example.com",
          "insecure_ssl" => "0",
          "content_type" => "form",
        },
        "updated_at" => "2019-01-01T10:00:00Z",
        "created_at" => "2019-01-01T10:00:00Z",
        "url" => "#{GitHub.api_url}/orgs/stark-industries/hooks/#{@org_hook.id}",
        "ping_url" => "#{GitHub.api_url}/orgs/stark-industries/hooks/#{@org_hook.id}/pings",
        "deliveries_url" => "#{GitHub.api_url}/orgs/stark-industries/hooks/#{@org_hook.id}/deliveries",
      }

      assert_equal expected_payload, output
    end
  end

  context "#integration_hook_hash" do
    test "payload has right values" do
      output = T.unsafe(self).integration_hook(@app_hook)

      expected_payload = {
        "type" => "App",
        "id" => @app_hook.id,
        "name" => "web",
        "active" => true,
        "events" => ["public"],
        "config" => {
          "url" => "http://example.com",
          "insecure_ssl" => "0",
          "content_type" => "form",
        },
        "updated_at" => "2019-01-01T10:00:00Z",
        "created_at" => "2019-01-01T10:00:00Z",
        "app_id" => @app_hook.installation_target.id,
        "deliveries_url" => "#{GitHub.api_url}/app/hook/deliveries",
      }

      assert_equal expected_payload, output
    end
  end
end
