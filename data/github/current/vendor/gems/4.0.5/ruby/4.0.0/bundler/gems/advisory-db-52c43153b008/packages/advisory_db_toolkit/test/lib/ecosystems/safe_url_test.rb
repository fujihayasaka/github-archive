# frozen_string_literal: true

require "test_helper"

module AdvisoryDBToolkit
  class EcosystemsSafeUrlTest < Minitest::Test
    SafeUrl = AdvisoryDBToolkit::Ecosystems::SafeUrl

    def test_appends_simple_package_name_to_base
      url = SafeUrl.build("https://registry.npmjs.org/", "lodash")
      assert_equal "https://registry.npmjs.org/lodash", url.to_s
    end

    def test_handles_base_without_trailing_slash
      url = SafeUrl.build("https://registry.npmjs.org", "lodash")
      assert_equal "https://registry.npmjs.org/lodash", url.to_s
    end

    def test_appends_under_base_path
      url = SafeUrl.build("https://crates.io/api/v1/", "crates", "serde")
      assert_equal "https://crates.io/api/v1/crates/serde", url.to_s
    end

    def test_preserves_legitimate_internal_slashes
      url = SafeUrl.build("https://pkg.go.dev/", "github.com/cloudflare/circl")
      assert_equal "https://pkg.go.dev/github.com/cloudflare/circl", url.to_s
    end

    def test_encodes_scoped_npm_package
      url = SafeUrl.build("https://registry.npmjs.org/", "@babel/core")
      assert_equal "registry.npmjs.org", url.host
      assert_equal "/%40babel/core", url.path
    end

    # --- SSRF / authority confusion vectors ---------------------------------

    def test_absolute_url_part_with_double_slash_is_rejected
      # The original PoC used `http://localhost:4646/...`. The `//` after the
      # scheme yields an empty path segment, which we reject outright.
      assert_raises(SafeUrl::UnsafePathError) do
        SafeUrl.build("https://registry.npmjs.org/", "http://localhost:4646/v1/jobs")
      end
    end

    def test_absolute_url_part_without_double_slash_cannot_replace_authority
      # Even if the payload avoids `//`, encoding pins the URL to the base host.
      url = SafeUrl.build("https://registry.npmjs.org/", "http:localhost:4646/v1/jobs?meta=true")
      assert_equal "https", url.scheme
      assert_equal "registry.npmjs.org", url.host
      assert_equal 443, url.port
      assert_nil url.query
      assert_equal "/http%3Alocalhost%3A4646/v1/jobs%3Fmeta%3Dtrue", url.path
    end

    def test_protocol_relative_part_is_rejected
      assert_raises(SafeUrl::UnsafePathError) do
        SafeUrl.build("https://registry.npmjs.org/", "//evil.example.com/x")
      end
    end

    def test_rooted_path_is_rejected
      assert_raises(SafeUrl::UnsafePathError) do
        SafeUrl.build("https://registry.npmjs.org/", "/etc/passwd")
      end
    end

    def test_dot_segments_are_rejected
      assert_raises(SafeUrl::UnsafePathError) do
        SafeUrl.build("https://crates.io/api/v1/", "../../admin")
      end
      assert_raises(SafeUrl::UnsafePathError) do
        SafeUrl.build("https://crates.io/api/v1/", "./x")
      end
    end

    def test_query_and_fragment_metacharacters_stay_in_path
      url = SafeUrl.build("https://registry.npmjs.org/", "a?b#c")
      assert_nil url.query
      assert_nil url.fragment
      assert_equal "/a%3Fb%23c", url.path
    end

    def test_userinfo_metacharacter_is_neutralized
      url = SafeUrl.build("https://registry.npmjs.org/", "evil.com:443@x")
      assert_equal "registry.npmjs.org", url.host
      assert_nil url.userinfo
      assert_equal "/evil.com%3A443%40x", url.path
    end

    def test_backslash_is_encoded
      url = SafeUrl.build("https://registry.npmjs.org/", "a\\b")
      assert_equal "/a%5Cb", url.path
    end

    def test_percent_is_double_encoded_to_block_smuggled_dot_segments
      url = SafeUrl.build("https://crates.io/api/v1/", "%2e%2e/admin")
      assert_equal "/api/v1/%252e%252e/admin", url.path
    end

    def test_empty_or_nil_part_is_rejected
      assert_raises(SafeUrl::UnsafePathError) { SafeUrl.build("https://registry.npmjs.org/", "") }
      assert_raises(SafeUrl::UnsafePathError) { SafeUrl.build("https://registry.npmjs.org/", nil) }
      assert_raises(SafeUrl::UnsafePathError) { SafeUrl.build("https://registry.npmjs.org/", "a//b") }
    end

    def test_non_http_base_is_rejected
      assert_raises(ArgumentError) { SafeUrl.build("ftp://registry.npmjs.org/", "lodash") }
      assert_raises(ArgumentError) { SafeUrl.build("registry.npmjs.org", "lodash") }
    end
  end
end
