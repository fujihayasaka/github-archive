# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsGenericTest < GitHub::TestCase
  VALID_URLS = %w(
    https://example.com
    http://example.com
    https://arbitrary.livejournal.com/some/path.html
    https://whatever.host.com/index.html?profile_id=1234
  )

  INVALID_URLS = %w(
    @login
    mailto:someone@emailz.com
    gopher://gopher.quux.org:70/1/
    /en-US/docs/
    https://badhost
    http://user@credentials.com
    http://user:pass@credentials.com
  )

  VALID_URLS.each do |url|
    test "accepts valid http(s) URL #{url}" do
      assert_predicate create(:social_account, url:), :valid?
    end
  end

  INVALID_URLS.each do |url|
    test "rejects invalid or non-http(s) URL #{url}" do
      refute_predicate create(:social_account, url:), :valid?
    end
  end

  context "#recognize" do
    test "identifies a non-Nodeinfo provider account by direct regexp match" do
      original_account = create(:social_account, url: "https://instagram.com/monalisa")
      result = original_account.recognize(defer_expensive: true)

      assert_equal "instagram", result.account.key
      assert_equal "https://instagram.com/monalisa", result.account.url
      refute result.deferred
      assert_nil result.nodeinfo_probe_result
    end

    if GitHub.nodeinfo_probe_enabled?
      test "identifies a cached Nodeinfo provider account" do
        Profiles::Kv.store.set("nodeinfo.software.v1:cached-server.com", "mastodon")

        original_account = create(:social_account, url: "https://cached-server.com/@monalisa")
        result = original_account.recognize(defer_expensive: true)

        assert_equal "mastodon", result.account.key
        assert_equal "https://cached-server.com/@monalisa", result.account.url
        refute result.deferred
        assert_predicate result.nodeinfo_probe_result, :success?
        refute_predicate result.nodeinfo_probe_result, :has_deferred_write?
      end

      test "identifies a non-cached Nodeinfo provider account when expensive checks are not deferred" do
        SocialAccounts::NodeinfoProbe.faraday_conf_block = lambda do |faraday|
          faraday.adapter(:test) do |stub|
            stub.get("https://uncached-server.com/.well-known/nodeinfo") do
              doc = {
                "links" => [
                  {
                    "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                    "href" => "https://uncached-server.com/nodeinfo/2.1",
                  }
                ]
              }
              [200, { "Content-Type" => "application/json" }, doc.to_json]
            end
            stub.get("https://uncached-server.com/nodeinfo/2.1") do
              doc = { "software" => { "name" => "hometown" } }
              [200, { "Content-Type" => "application/json" }, doc.to_json]
            end
          end
        end

        original_account = create(:social_account, url: "https://uncached-server.com/@monalisa")
        result = original_account.recognize(defer_expensive: false)

        assert_equal "hometown", result.account.key
        assert_equal "https://uncached-server.com/@monalisa", result.account.url
        refute result.deferred
        assert_predicate result.nodeinfo_probe_result, :success?
        assert_predicate result.nodeinfo_probe_result, :has_deferred_write?
      end

      test "does not identify a non-cached Nodeinfo provider account when expensive checks are deferred" do
        original_account = create(:social_account, url: "https://uncached-server.com/@monalisa")
        result = original_account.recognize(defer_expensive: true)

        assert_equal original_account, result.account
        assert result.deferred
        refute_predicate result.nodeinfo_probe_result, :success?
        refute_predicate result.nodeinfo_probe_result, :has_deferred_write?
      end
    else
      test "does not identify a cached Nodeinfo provider account" do
        Profiles::Kv.store.set("nodeinfo.software.v1:cached-server.com", "mastodon")

        original_account = create(:social_account, url: "https://cached-server.com/@monalisa")
        result = original_account.recognize(defer_expensive: true)

        assert_equal original_account, result.account
        refute result.deferred
        assert_nil result.nodeinfo_probe_result
      end

      test "does not identify a non-cached Nodeinfo provider account when expensive checks are not deferred" do
        SocialAccounts::NodeinfoProbe.faraday_conf_block = lambda do |faraday|
          faraday.adapter(:test) {}
        end

        original_account = create(:social_account, url: "https://uncached-server.com/@monalisa")
        result = original_account.recognize(defer_expensive: false)

        assert_equal original_account, result.account
        refute result.deferred
        assert_nil result.nodeinfo_probe_result
      end

      test "does not identify a non-cached Nodeinfo provider account when expensive checks are deferred" do
        original_account = create(:social_account, url: "https://uncached-server.com/@monalisa")
        result = original_account.recognize(defer_expensive: true)

        assert_equal original_account, result.account
        refute result.deferred
        assert_nil result.nodeinfo_probe_result
      end
    end

    test "does not identify a URL that doesn't match anything" do
      original_account = create(:social_account, url: "https://uncached-server.com/accountz/monalisa")
      result = original_account.recognize(defer_expensive: true)

      assert_equal original_account, result.account
      refute result.deferred
      assert_nil result.nodeinfo_probe_result
    end
  end
end
