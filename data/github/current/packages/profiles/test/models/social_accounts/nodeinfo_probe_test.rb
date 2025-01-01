# typed: true
# frozen_string_literal: true

require "test_helper"

class SocialAccountsNodeinfoProbeTest < GitHub::TestCase
  teardown do
    SocialAccounts::NodeinfoProbe.faraday_conf_block = -> (conn) { conn.adapter(Faraday.default_adapter) }
  end

  def stub_requests
    SocialAccounts::NodeinfoProbe.faraday_conf_block = lambda do |faraday|
      faraday.adapter(:test) do |stub|
        yield stub
      end
    end
  end

  def make_json_response(doc)
    [200, { "Content-Type" => "application/json" }, doc.to_json]
  end

  if GitHub.nodeinfo_probe_enabled?
    test "returns unknown when the host is not in the cache and cache-only is specified" do
      stub_requests {}

      result = SocialAccounts::NodeinfoProbe.call(host: "forgotten-elephant.com", cached_only: true)

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "no-cached-value", result.details["gh.nodeinfo.reason"]

      refute Profiles::Kv.store.exists("nodeinfo.software.v1:forgotten-elephant.com").value!
    end

    test "returns reported software name from cache when cache-only is specified" do
      Profiles::Kv.store.set("nodeinfo.software.v1:remembered-elephant.com", "mastodon")
      stub_requests {}

      result = SocialAccounts::NodeinfoProbe.call(host: "remembered-elephant.com", cached_only: true)

      assert_predicate result, :success?
      assert_predicate result, :cached?
      assert_equal "mastodon", result.software_name
    end

    test "returns reported software name from cache when cache-only is not specified" do
      Profiles::Kv.store.set("nodeinfo.software.v1:elephant-pics.com", "pixelfed")
      stub_requests {}

      result = SocialAccounts::NodeinfoProbe.call(host: "elephant-pics.com")

      assert_predicate result, :success?
      assert_predicate result, :cached?
      assert_equal "pixelfed", result.software_name
    end

    test "returns unknown when the host cannot be resolved" do
      stub_requests do |stub|
        stub.get("https://not-found.com/.well-known/nodeinfo") { raise Faraday::ConnectionFailed.new("") }
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "not-found.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "http-error", result.details["gh.nodeinfo.reason"]
      assert_equal "https://not-found.com/.well-known/nodeinfo", result.details["http.url"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:not-found.com").value!
    end

    test "returns unknown when the host fails the .well-known request" do
      stub_requests do |stub|
        stub.get("https://modern-elephant.com/.well-known/nodeinfo") do
          [404, { "Content-Type" => "text/plain" }, "Not found"]
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "modern-elephant.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "unsuccessful-http-response", result.details["gh.nodeinfo.reason"]
      assert_equal "https://modern-elephant.com/.well-known/nodeinfo", result.details["http.url"]
      assert_equal 404, result.details["http.status_code"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:modern-elephant.com").value!
    end

    test "returns unknown when the host's well-known response is not JSON" do
      stub_requests do |stub|
        stub.get("https://not-json.com/.well-known/nodeinfo") do
          [200, { "Content-Type" => "text/plain" }, "<_<"]
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "not-json.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "non-json-http-response", result.details["gh.nodeinfo.reason"]
      assert_equal "https://not-json.com/.well-known/nodeinfo", result.details["http.url"]
      assert_equal "text/plain", result.details["http.content_type"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:not-json.com").value!
    end

    test "returns unknown when the host request fails with an unexpected error" do
      stub_requests do |stub|
        stub.get("https://timeout.com/.well-known/nodeinfo") { raise Faraday::TimeoutError.new("") }
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "timeout.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "uncaught-network-error", result.details["gh.nodeinfo.reason"]
      assert_equal "https://timeout.com/.well-known/nodeinfo", result.details["http.url"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:timeout.com").value!
    end

    test "returns unknown when the host's well-known response contains no recognized schema" do
      stub_requests do |stub|
        stub.get("https://misbehaving-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "https://what-schema-is-this.com/",
                "href" => "https://misbehaving-elephant.com/lol",
              }
            ]
          })
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "misbehaving-elephant.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "no-schema-link", result.details["gh.nodeinfo.reason"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:misbehaving-elephant.com").value!
    end

    test "returns unknown when the info URL cannot be resolved" do
      stub_requests do |stub|
        stub.get("https://misbehaving-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                "href" => "https://misbehaving-elephant.com/lmao",
              }
            ]
          })
        end
        stub.get("https://misbehaving-elephant.com/lmao") { raise Faraday::ConnectionFailed.new("") }
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "misbehaving-elephant.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "http-error", result.details["gh.nodeinfo.reason"]
      assert_equal "https://misbehaving-elephant.com/lmao", result.details["http.url"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:misbehaving-elephant.com").value!
    end

    test "returns unknown when the info request fails" do
      stub_requests do |stub|
        stub.get("https://misbehaving-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                "href" => "https://misbehaving-elephant.com/pffft",
              }
            ]
          })
        end
        stub.get("https://misbehaving-elephant.com/pffft") do
          [404, { "Content-Type" => "text/plain" }, "Nice try"]
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "misbehaving-elephant.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "unsuccessful-http-response", result.details["gh.nodeinfo.reason"]
      assert_equal "https://misbehaving-elephant.com/pffft", result.details["http.url"]
      assert_equal 404, result.details["http.status_code"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:misbehaving-elephant.com").value!
    end

    test "returns unknown when the info response contains unparseable JSON" do
      stub_requests do |stub|
        stub.get("https://misbehaving-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                "href" => "https://misbehaving-elephant.com/lying-about-json",
              }
            ]
          })
        end
        stub.get("https://misbehaving-elephant.com/lying-about-json") do
          [200, { "Content-Type" => "application/json" }, "OOOPS"]
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "misbehaving-elephant.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "json-parsing-error", result.details["gh.nodeinfo.reason"]
      assert_equal "https://misbehaving-elephant.com/lying-about-json", result.details["http.url"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:misbehaving-elephant.com").value!
    end

    test "returns unknown when the info response contains JSON with unexpected structure" do
      stub_requests do |stub|
        stub.get("https://misbehaving-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                "href" => "https://misbehaving-elephant.com/lying-about-schema",
              }
            ]
          })
        end
        stub.get("https://misbehaving-elephant.com/lying-about-schema") do
          make_json_response({ "lmao" => "lol" })
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "misbehaving-elephant.com")

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "missing-software-name", result.details["gh.nodeinfo.reason"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:misbehaving-elephant.com").value!
    end

    test "returns and caches reported software name retrieved from server" do
      stub_requests do |stub|
        stub.get("https://happy-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                "href" => "https://happy-elephant.com/nodeinfo/2.1",
              }
            ]
          })
        end
        stub.get("https://happy-elephant.com/nodeinfo/2.1") do
          make_json_response({ "software" => { "name" => "mastodon" } })
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "happy-elephant.com")

      assert_predicate result, :success?
      refute_predicate result, :cached?
      refute_predicate result, :has_deferred_write?
      assert_equal "mastodon", result.software_name
      assert_equal "mastodon", Profiles::Kv.store.get("nodeinfo.software.v1:happy-elephant.com").value!
    end

    test "returns and defers caching of reported software name retrieved from server" do
      stub_requests do |stub|
        stub.get("https://happy-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                "href" => "https://happy-elephant.com/nodeinfo/2.1",
              }
            ]
          })
        end
        stub.get("https://happy-elephant.com/nodeinfo/2.1") do
          make_json_response({ "software" => { "name" => "mastodon" } })
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "happy-elephant.com", defer_cache_write: true)

      assert_predicate result, :success?
      assert_predicate result, :has_deferred_write?
      assert_equal "mastodon", result.software_name
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:happy-elephant.com").value!

      result.perform_deferred_write

      assert_equal "mastodon", Profiles::Kv.store.get("nodeinfo.software.v1:happy-elephant.com").value!
    end

    test "follows redirects" do
      stub_requests do |stub|
        stub.get("https://redirected-elephant.com/.well-known/nodeinfo") do
          [301, { "Location" => "https://different-elephant.com/.well-known/nodeinfo" }, ""]
        end
        stub.get("https://different-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
                "href" => "https://some-elephant.com/nodeinfo/2.1",
              }
            ]
          })
        end

        stub.get("https://some-elephant.com/nodeinfo/2.1") do
          [301, { "Location" => "https://more-elephants.com/nodeinfo/2.1" }, ""]
        end
        stub.get("https://more-elephants.com/nodeinfo/2.1") do
          make_json_response({ "software" => { "name" => "mastodon" } })
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "redirected-elephant.com")

      assert_predicate result, :success?
      refute_predicate result, :cached?
      refute_predicate result, :has_deferred_write?
      assert_equal "mastodon", result.software_name
      assert_equal "mastodon", Profiles::Kv.store.get("nodeinfo.software.v1:redirected-elephant.com").value!
    end

    test "refuses to redirect to non-https URLs" do
      stub_requests do |stub|
        stub.get("https://redirected-elephant.com/.well-known/nodeinfo") do
          [301, { "Location" => "ftp://bad-elephant.com/" }, ""]
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "redirected-elephant.com")

      refute_predicate result, :success?
      assert_equal "refused-http-redirect", result.details["gh.nodeinfo.reason"]
      assert_equal "https://redirected-elephant.com/.well-known/nodeinfo", result.details["http.url"]
      assert_equal "ftp://bad-elephant.com/", result.details["gh.nodeinfo.redirect.location"]
      refute Profiles::Kv.store.exists("nodeinfo.software.v1:redirected-elephant.com").value!
    end

    test "follows the highest-versioned schema link in the well-known response" do
      stub_requests do |stub|
        stub.get("https://happy-elephant.com/.well-known/nodeinfo") do
          make_json_response({
            "links" => [
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.0",
                "href" => "https://happy-elephant.com/nodeinfo/2.0",
              },
              {
                "rel" => "http://nodeinfo.diaspora.software/ns/schema/1.1",
                "href" => "https://happy-elephant.com/nodeinfo/lolnope",
              }
            ]
          })
        end
        stub.get("https://happy-elephant.com/nodeinfo/2.0") do
          make_json_response({ "software" => { "name" => "mastodon" } })
        end
      end

      result = SocialAccounts::NodeinfoProbe.call(host: "happy-elephant.com")

      assert_predicate result, :success?
      assert_equal "mastodon", result.software_name
      assert_equal "mastodon", Profiles::Kv.store.get("nodeinfo.software.v1:happy-elephant.com").value!
    end
  else
    # Nodeinfo probe is disabled
    test "returns unknown when the host is in the cache and nodeinfo probe is disabled" do
      stub_requests {}
      Profiles::Kv.store.set("nodeinfo.software.v1:hidden-elephant.com", "mastodon")

      result = SocialAccounts::NodeinfoProbe.call(host: "hidden-elephant.com", cached_only: true)

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "nodeinfo-probe-disabled", result.details["gh.nodeinfo.reason"]
    end

    test "returns unknown when the host is not in the cache and nodeinfo probe is disabled" do
      stub_requests {}

      result = SocialAccounts::NodeinfoProbe.call(host: "forbidden-elephant.com", cached_only: true)

      assert_equal "unknown", result.software_name
      refute_predicate result, :success?
      assert_equal "nodeinfo-probe-disabled", result.details["gh.nodeinfo.reason"]

      refute Profiles::Kv.store.exists("nodeinfo.software.v1:forbidden-elephant.com").value!
    end
  end
end
