# typed: true
# frozen_string_literal: true

require "test_helper"
require "oauth_util"

class OauthUtilTest < GitHub::TestCase
  fixtures do
    @app2 = create :oauth_application

    @integration = create(:integration)
    @integration_callback_url = create(:application_callback_url, application: @integration, url: "http://github.com/foo")

    @integration2 = create(:integration, application_callback_urls_attributes: [
      { url: "http://github.com" },
      { url: "http://github.com/foo" },
      { url: "http://github.com/foo?param1=value1&param2=value2" },
      { url: "http://integration.github.com" }
    ])
  end

  setup do
    @object = Object.new
    @object.extend OauthUtil
    @app = OauthApplication.new callback_url: "http://github.com/foo"
    @app2.set_application_callback_urls(
      "http://github.com",
      "http://github.com/foo",
      "http://github.com/foo?param1=value1&param2=value2",
      "http://integration.github.com",
    )
    @app2.save!
  end

  test "verifies good redirection uris for single callback applications" do
    # Special cased URL
    assert @object.valid_redirect_uri?(@app, "https://github.com/login/oauth/success")

    # Matching path and subpaths
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/bar")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/")
    assert @object.valid_redirect_uri?(@app, "http://github.com:80/foo/bar")
    assert @object.valid_redirect_uri?(@app, "http://github.com:80/foo/bar")
    @app.callback_url = "http://github.com/"
    assert @object.valid_redirect_uri?(@app, "http://github.com")
    assert @object.valid_redirect_uri?(@app, "http://github.com/")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/bar")
    @app.callback_url = "http://github.com"
    assert @object.valid_redirect_uri?(@app, "http://github.com/")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/bar")
    @app.callback_url = "http://github.com/foo"

    # A single trailing dot is allowed, as URL normalization will parse this
    # as `http://github.com/foo` (a fully qualified domain name).
    assert @object.valid_redirect_uri?(@app, "http://github.com./foo")

    # Subdomains with matching path
    assert @object.valid_redirect_uri?(@app, "http://www.github.com:80/foo/bar")
    assert @object.valid_redirect_uri?(@app, "http://ヒキワリ.ナットウ.github.com/foo")

    # Matching inferred ports.
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/bar")
    assert @object.valid_redirect_uri?(@app, "http://github.com:80/foo/bar")

    # Matching userinfo
    assert @object.valid_redirect_uri?(@app, "http://@github.com/foo")
    @app.callback_uri.user = "test"
    assert @object.valid_redirect_uri?(@app, "http://test@github.com/foo/bar")
    @app.callback_uri.user = nil

    # Disregards trailing slash
    @app.callback_url = "http://github.com/foo/"
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo")
    assert @object.valid_redirect_uri?(@app, "http://github.com/foo/bar")

    # Custom ports
    @app.callback_url = "http://github.com:81/foo"
    assert @object.valid_redirect_uri?(@app, "http://github.com:81/foo/bar")
  end

  test "verifies good redirection uris for multiple callback applications" do
    # Special cased URL
    assert @object.valid_redirect_uri?(@app2, "https://github.com/login/oauth/success")

    # Exact matches
    @app2.application_callback_urls.each do |callback_url|
      assert @object.valid_redirect_uri?(@app2, callback_url.url)
    end
  end

  test "catches bad redirection uris for single callback applications" do
    # Bad URLs
    refute @object.valid_redirect_uri?(@app, "blah")

    # Non-matching hostnames
    refute @object.valid_redirect_uri?(@app, "http://svnhub.com/foo")
    refute @object.valid_redirect_uri?(@app, "http://github.com.evil.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://wwwgithub.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://evil.com\\.github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app, "https://some_attacker_domain%2523.gist.github.com/auth/github/callback")

    # Blank hostnames
    refute @object.valid_redirect_uri?(@app, "")
    refute @object.valid_redirect_uri?(@app, nil)

    # See https://github.com/github/github/issues/35213 for an explanation of
    # the below "trailing dots" tests.

    # More than one trailing dot is not allowed, as URL normalization will parse
    # this as `http://github.com../foo`.
    refute @object.valid_redirect_uri?(@app, "http://github.com../foo")

    # URLs with non-printable characters
    refute @object.valid_redirect_uri?(@app, "http://sub\x00.github.com/foo")
    refute @object.valid_redirect_uri?(@app, "http://sub\x08.github.com/foo")
    refute @object.valid_redirect_uri?(@app, "http://sub\x0a.github.com/foo")

    # Non-matching paths
    refute @object.valid_redirect_uri?(@app, "http://github.com/food")
    refute @object.valid_redirect_uri?(@app, "http://github.com/bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/../bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/%2e./bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/.%2e/bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/%2e%2e/bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com/")
    refute @object.valid_redirect_uri?(@app, "http://github.com")

    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/../../../")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/..%2F..%2F..%2F")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/..\..\..\\")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/..%5C..%5C..%5C")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/.%0A./lol")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/.%0C./lol")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/.%0D./lol")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/.%00./lol")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/. ./lol")
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar/%0A")

    # Non-matching inferred ports
    refute @object.valid_redirect_uri?(@app, "http://github.com:443/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com:8080/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://github.com:81/foo")

    @app.callback_url = "http://github.com:81/foo"
    refute @object.valid_redirect_uri?(@app, "http://github.com:82/foo")
    @app.callback_url = "http://github.com/foo"

    # Non-matching schemes
    refute @object.valid_redirect_uri?(@app, "https://github.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app, "https://github.com/foo")
    refute @object.valid_redirect_uri?(@app, "https://github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app, "https://github.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app, "ftp://github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app, "javascript://github.com/foo/%250A%250Dalert(9)")
    refute @object.valid_redirect_uri?(@app, "http%0A://evil.com/foo")

    @app.callback_url = "javascript://something"
    refute @object.valid_redirect_uri?(@app, "javascript://something")
    @app.callback_url = "http://github.com/foo"

    # Non-matching userinfo
    refute @object.valid_redirect_uri?(@app, "http://evil.com@github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://evil.com\@github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://evil.com\\@github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app, "http://evil.com:80@github.com/foo/bar")

    @app.callback_uri.user = "test"
    refute @object.valid_redirect_uri?(@app, "http://github.com/foo/bar")
    @app.callback_uri.user = nil

    @app.callback_url = "http://example.com"
    refute @object.valid_redirect_uri?(@app, "http://github.com\\github-oauth@example.com")
  end

  test "catches bad redirection uris for multiple callback applications" do
    # Bad URLs
    refute @object.valid_redirect_uri?(@app2, "blah")

    # Non-matching hostnames
    refute @object.valid_redirect_uri?(@app2, "http://svnhub.com")

    # Non-matching subdomain
    refute @object.valid_redirect_uri?(@app2, "http://subdomain.github.com")

    # Non-matching query parameters
    refute @object.valid_redirect_uri?(@app2, "http://github.com?param1=value1&param2=value2&param3=value3")

    # Query parameters that don't match order exactly
    refute @object.valid_redirect_uri?(@app2, "http://github.com?param2=value2&param1=value1")

    # Hostname with a trailing slash
    refute @object.valid_redirect_uri?(@app2, "http://github.com/")

    # Multiple callback URL validation is incredibly strict. So, anything
    # other than an exact match should fail. However, for now, we include
    # additional tests to validate that edge case behavior we allow for single
    # callback URL applications is blocked for multiple callback URLs
    # applications.

    # Tests that pass for single callback applications but failf or multiple
    # callaback applications

    # Any non-exact paths and subpaths
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/")
    refute @object.valid_redirect_uri?(@app2, "http://github.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com:80/foo/bar")

    # Any subdomains with or subpath
    refute @object.valid_redirect_uri?(@app2, "http://www.github.com:80/foo/bar")

    # Any inferred ports.
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com:80/foo/bar")

    # Any userinfo
    refute @object.valid_redirect_uri?(@app2, "http://@github.com/foo")
    @app2.callback_uri.user = "test"
    refute @object.valid_redirect_uri?(@app2, "http://test@github.com/foo/bar")
    @app2.callback_uri.user = nil

    # Any trailing slash
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/")

    # Tests that fail for single callback applications and also fail for
    # mulitple callback applications.

    # Bad URLs
    refute @object.valid_redirect_uri?(@app2, "blah")

    # Non-matching hostnames
    refute @object.valid_redirect_uri?(@app2, "http://svnhub.com/foo")
    refute @object.valid_redirect_uri?(@app2, "http://github.com.evil.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://wwwgithub.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://evil.com\\.github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "https://some_attacker_domain%2523.gist.github.com/auth/github/callback")

    refute @object.valid_redirect_uri?(@app2, "http://ヒキワリ.ナットウ.github.com/foo")

    # Blank hostnames
    refute @object.valid_redirect_uri?(@app2, "")

    assert_raises ArgumentError do
      @object.valid_redirect_uri?(@app2, nil)
    end

    # See https://github.com/github/github/issues/35213 for an explanation of
    # the below "trailing dots" tests.

    # A single trailing dot is allowed, as URL normalization will parse this
    # as `http://github.com/foo` (a fully qualified domain name).
    refute @object.valid_redirect_uri?(@app2, "http://github.com./foo")
    # More than one trailing dot is not allowed, as URL normalization will parse
    # this as `http://github.com../foo`.
    refute @object.valid_redirect_uri?(@app2, "http://github.com../foo")

    # URLs with non-printable characters
    refute @object.valid_redirect_uri?(@app2, "http://sub\x00.github.com/foo")
    refute @object.valid_redirect_uri?(@app2, "http://sub\x08.github.com/foo")
    refute @object.valid_redirect_uri?(@app2, "http://sub\x0a.github.com/foo")

    # Non-matching paths
    refute @object.valid_redirect_uri?(@app2, "http://github.com/food")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/../bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/%2e./bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/.%2e/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/%2e%2e/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/")

    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/../../../")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/..%2F..%2F..%2F")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/..\..\..\\")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/..%5C..%5C..%5C")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/.%0A./lol")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/.%0C./lol")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/.%0D./lol")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/.%00./lol")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/. ./lol")
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar/%0A")

    # Non-matching inferred ports
    refute @object.valid_redirect_uri?(@app2, "http://github.com:443/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com:8080/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://github.com:81/foo")

    # Non-matching schemes
    refute @object.valid_redirect_uri?(@app2, "https://github.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "https://github.com/foo")
    refute @object.valid_redirect_uri?(@app2, "https://github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "https://github.com:80/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "ftp://github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "javascript://github.com/foo/%250A%250Dalert(9)")
    refute @object.valid_redirect_uri?(@app2, "http%0A://evil.com/foo")

    # Non-matching userinfo
    refute @object.valid_redirect_uri?(@app2, "http://evil.com@github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://evil.com\@github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://evil.com\\@github.com/foo/bar")
    refute @object.valid_redirect_uri?(@app2, "http://evil.com:80@github.com/foo/bar")

    @app2.callback_uri.user = "test"
    refute @object.valid_redirect_uri?(@app2, "http://github.com/foo/bar")
    @app2.callback_uri.user = nil
  end

  test "checks subdomains correctly" do
    assert @object.subdomain? "github.com", "foo.github.com"
    assert @object.subdomain? "github.com", "foo.bar.github.com"
    refute @object.subdomain? "github.com", "foogithub.com"
    refute @object.subdomain? "github.com", "github.com.foo"
    # See https://github.com/github/github/issues/35213 for an explanation of
    # the below "trailing dots" tests.
    refute @object.subdomain? "github.com", "github.com."
    refute @object.subdomain? "github.com", "github.com.."
  end

  test "checks subpaths correctly" do
    assert @object.subpath? "/", "/foo"
    assert @object.subpath? "/", "/foo/bar"
    assert @object.subpath? "", "/"
    assert @object.subpath? "/", ""
    assert @object.subpath? "/foo", "/foo/bar"
    assert @object.subpath? "/foo", "/foo/bar/baz"
    refute @object.subpath? "/foo", "/foobar"
    refute @object.subpath? "/foo", "/foobar/baz"
  end

  test "builds success redirect url with no query" do
    assert_equal "http://github.com/foo?code=1%262",
      @object.redirect_url(@app.callback_url, code: "1&2")
  end

  test "builds success redirect url with empty query" do
    assert_equal "http://github.com/foo?code=1%262",
      @object.redirect_url("#{@app.callback_url}?", code: "1&2")
  end

  test "builds success redirect url with existing query" do
    assert_equal "http://github.com/foo?a=1&code=1%262",
      @object.redirect_url("#{@app.callback_url}?a=1", code: "1&2")
  end

  test "builds success redirect url with clashing query" do
    assert_equal "http://github.com/foo?a=1&a=1%262",
      @object.redirect_url("#{@app.callback_url}?a=1", a: "1&2")
  end

  test "builds success redirect url with state if it is not nil" do
    assert_equal "http://github.com/foo?code=1&state=state",
      @object.redirect_url(
        @app.callback_url,
        code: "1",
        state: "state",
      )
  end

  test "builds success redirect url without state if it is nil" do
    assert_equal "http://github.com/foo?code=1",
      @object.redirect_url(
        @app.callback_url,
        code: "1",
        state: nil,
      )
  end

  context "GitHub apps" do

    test "verifies good redirection uris for single callback applications" do
      # Special cased URL
      assert @object.valid_redirect_uri?(@integration, "https://github.com/login/oauth/success")

      # Matching path and subpaths
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/")
      assert @object.valid_redirect_uri?(@integration, "http://github.com:80/foo/bar")
      assert @object.valid_redirect_uri?(@integration, "http://github.com:80/foo/bar")
      assert @integration_callback_url.update(url: "http://github.com/"); @integration_callback_url.reload
      @object.valid_redirect_uri?(@integration, "http://github.com")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar")
      assert @integration_callback_url.update(url: "http://github.com"); @integration_callback_url.reload
      assert @object.valid_redirect_uri?(@integration, "http://github.com/")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar")
      assert @integration_callback_url.update(url: "http://github.com/foo"); @integration_callback_url.reload

      # A single trailing dot is allowed, as URL normalization will parse this
      # as `http://github.com/foo` (a fully qualified domain name).
      assert @object.valid_redirect_uri?(@integration, "http://github.com./foo")

      # Subdomains with matching path
      assert @object.valid_redirect_uri?(@integration, "http://www.github.com:80/foo/bar")
      assert @object.valid_redirect_uri?(@integration, "http://ヒキワリ.ナットウ.github.com/foo")

      # Matching inferred ports.
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar")
      assert @object.valid_redirect_uri?(@integration, "http://github.com:80/foo/bar")

      # Matching userinfo
      assert @object.valid_redirect_uri?(@integration, "http://@github.com/foo")
      @integration.stubs(callback_uri: Addressable::URI.parse("http://test@github.com/"))
      assert @object.valid_redirect_uri?(@integration, "http://test@github.com/foo/bar")
      @integration.unstub(:callback_uri)

      # Disregards trailing slash
      @integration_callback_url.update(url: "http://github.com/foo/"); @integration_callback_url.reload
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo")
      assert @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar")

      # Custom ports
      @integration_callback_url.update(url: "http://github.com:81/foo"); @integration_callback_url.reload
      assert @object.valid_redirect_uri?(@integration, "http://github.com:81/foo/bar")
    end

    test "catches bad redirection uris for single callback applications" do
      # Bad URLs
      refute @object.valid_redirect_uri?(@integration, "blah")

      # Non-matching hostnames
      refute @object.valid_redirect_uri?(@integration, "http://svnhub.com/foo")
      refute @object.valid_redirect_uri?(@integration, "http://github.com.evil.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://wwwgithub.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://evil.com\\.github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "https://some_attacker_domain%2523.gist.github.com/auth/github/callback")

      # Blank hostnames
      refute @object.valid_redirect_uri?(@integration, "")
      refute @object.valid_redirect_uri?(@integration, nil)

      # See https://github.com/github/github/issues/35213 for an explanation of
      # the below "trailing dots" tests.

      # More than one trailing dot is not allowed, as URL normalization will parse
      # this as `http://github.com../foo`.
      refute @object.valid_redirect_uri?(@integration, "http://github.com../foo")

      # URLs with non-printable characters
      refute @object.valid_redirect_uri?(@integration, "http://sub\x00.github.com/foo")
      refute @object.valid_redirect_uri?(@integration, "http://sub\x08.github.com/foo")
      refute @object.valid_redirect_uri?(@integration, "http://sub\x0a.github.com/foo")

      # Non-matching paths
      refute @object.valid_redirect_uri?(@integration, "http://github.com/food")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/../bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/%2e./bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/.%2e/bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/%2e%2e/bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/")
      refute @object.valid_redirect_uri?(@integration, "http://github.com")

      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/../../../")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/..%2F..%2F..%2F")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/..\..\..\\")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/..%5C..%5C..%5C")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/.%0A./lol")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/.%0C./lol")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/.%0D./lol")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/.%00./lol")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/. ./lol")
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar/%0A")

      # Non-matching inferred ports
      refute @object.valid_redirect_uri?(@integration, "http://github.com:443/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com:8080/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://github.com:81/foo")

      @integration_callback_url.update(url: "http://github.com:81/foo"); @integration_callback_url.reload
      refute @object.valid_redirect_uri?(@integration, "http://github.com:82/foo")
      @integration_callback_url.update(url: "http://github.com/foo"); @integration_callback_url.reload

      # Non-matching schemes
      refute @object.valid_redirect_uri?(@integration, "https://github.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "https://github.com/foo")
      refute @object.valid_redirect_uri?(@integration, "https://github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "https://github.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "ftp://github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "javascript://github.com/foo/%250A%250Dalert(9)")
      refute @object.valid_redirect_uri?(@integration, "http%0A://evil.com/foo")

      # Non-matching userinfo
      refute @object.valid_redirect_uri?(@integration, "http://evil.com@github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://evil.com\@github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://evil.com\\@github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration, "http://evil.com:80@github.com/foo/bar")

      @integration.stubs(callback_uri: Addressable::URI.parse("http://test@github.com/"))
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo/bar")
      @integration.unstub(:callback_uri)

      @integration_callback_url.update(url: "http://example.com"); @integration_callback_url.reload
      refute @object.valid_redirect_uri?(@integration, "http://github.com\\github-oauth@example.com")
    end

    test "catches applications with missing callback_uri" do
      @integration_callback_url.destroy; @integration.reload
      refute @object.valid_redirect_uri?(@integration, "http://github.com/foo")
    end

    test "verifies good redirection uris for multiple callback applications" do
      # Special cased URL
      assert @object.valid_redirect_uri?(@integration2, "https://github.com/login/oauth/success")

      # Exact matches
      @app2.application_callback_urls.each do |callback_url|
        assert @object.valid_redirect_uri?(@integration2, callback_url.url)
      end
    end

    test "catches bad redirection uris for multiple callback applications" do
      # Bad URLs
      refute @object.valid_redirect_uri?(@integration2, "blah")

      # Non-matching hostnames
      refute @object.valid_redirect_uri?(@integration2, "http://svnhub.com")

      # Non-matching subdomain
      refute @object.valid_redirect_uri?(@integration2, "http://subdomain.github.com")

      # Non-matching query parameters
      refute @object.valid_redirect_uri?(@integration2, "http://github.com?param1=value1&param2=value2&param3=value3")

      # Query parameters that don't match order exactly
      refute @object.valid_redirect_uri?(@integration2, "http://github.com?param2=value2&param1=value1")

      # Hostname with a trailing slash
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/")

      # Multiple callback URL validation is incredibly strict. So, anything
      # other than an exact match should fail. However, for now, we include
      # additional tests to validate that edge case behavior we allow for single
      # callback URL applications is blocked for multiple callback URLs
      # applications.

      # Tests that pass for single callback applications but failf or multiple
      # callaback applications

      # Any non-exact paths and subpaths
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com:80/foo/bar")

      # Any subdomains with or subpath
      refute @object.valid_redirect_uri?(@integration2, "http://www.github.com:80/foo/bar")

      # Any inferred ports.
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com:80/foo/bar")

      # Any userinfo
      refute @object.valid_redirect_uri?(@integration2, "http://@github.com/foo")
      @integration2.callback_uri.user = "test"
      refute @object.valid_redirect_uri?(@integration2, "http://test@github.com/foo/bar")
      @integration2.callback_uri.user = nil

      # Any trailing slash
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/")

      # Tests that fail for single callback applications and also fail for
      # mulitple callback applications.

      # Bad URLs
      refute @object.valid_redirect_uri?(@integration2, "blah")

      # Non-matching hostnames
      refute @object.valid_redirect_uri?(@integration2, "http://svnhub.com/foo")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com.evil.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://wwwgithub.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://evil.com\\.github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "https://some_attacker_domain%2523.gist.github.com/auth/github/callback")

      refute @object.valid_redirect_uri?(@integration2, "http://ヒキワリ.ナットウ.github.com/foo")

      # Blank hostnames
      refute @object.valid_redirect_uri?(@integration2, "")

      assert_raises ArgumentError do
        @object.valid_redirect_uri?(@integration2, nil)
      end

      # See https://github.com/github/github/issues/35213 for an explanation of
      # the below "trailing dots" tests.

      # A single trailing dot is allowed, as URL normalization will parse this
      # as `http://github.com/foo` (a fully qualified domain name).
      refute @object.valid_redirect_uri?(@integration2, "http://github.com./foo")
      # More than one trailing dot is not allowed, as URL normalization will parse
      # this as `http://github.com../foo`.
      refute @object.valid_redirect_uri?(@integration2, "http://github.com../foo")

      # URLs with non-printable characters
      refute @object.valid_redirect_uri?(@integration2, "http://sub\x00.github.com/foo")
      refute @object.valid_redirect_uri?(@integration2, "http://sub\x08.github.com/foo")
      refute @object.valid_redirect_uri?(@integration2, "http://sub\x0a.github.com/foo")

      # Non-matching paths
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/food")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/../bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/%2e./bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/.%2e/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/%2e%2e/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/")

      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/../../../")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/..%2F..%2F..%2F")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/..\..\..\\")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/..%5C..%5C..%5C")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/.%0A./lol")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/.%0C./lol")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/.%0D./lol")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/.%00./lol")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/. ./lol")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar/%0A")

      # Non-matching inferred ports
      refute @object.valid_redirect_uri?(@integration2, "http://github.com:443/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com:8080/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://github.com:81/foo")

      # Non-matching schemes
      refute @object.valid_redirect_uri?(@integration2, "https://github.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "https://github.com/foo")
      refute @object.valid_redirect_uri?(@integration2, "https://github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "https://github.com:80/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "ftp://github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "javascript://github.com/foo/%250A%250Dalert(9)")
      refute @object.valid_redirect_uri?(@integration2, "http%0A://evil.com/foo")

      # Non-matching userinfo
      refute @object.valid_redirect_uri?(@integration2, "http://evil.com@github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://evil.com\@github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://evil.com\\@github.com/foo/bar")
      refute @object.valid_redirect_uri?(@integration2, "http://evil.com:80@github.com/foo/bar")

      @integration2.stubs(callback_uri: Addressable::URI.parse("http://test@github.com/"))
      refute @object.valid_redirect_uri?(@integration2, "http://github.com/foo/bar")
      @integration2.unstub(:callback_uri)
    end
  end

  test "allows non matching ports with localhost" do
    app = create :oauth_application, callback_url: "http://localhost:3000"
    assert @object.valid_redirect_uri?(app, "http://localhost:5000/foo/bar")

    app.update(callback_url: "http://127.0.0.1:3000")
    app.reload

    assert @object.valid_redirect_uri?(app, "http://127.0.0.1:5000/foo/bar")

    app.set_application_callback_urls(
      "http://localhost/foo/bar",
      "http://127.0.0.1/foo/bar",
    )
    app.save!

    assert @object.valid_redirect_uri?(app, "http://localhost:5000/foo/bar")
    assert @object.valid_redirect_uri?(app, "http://127.0.0.1:5000/foo/bar")

    refute @object.valid_redirect_uri?(app, "http://localhost:5000/foo")
    refute @object.valid_redirect_uri?(app, "http://127.0.0.1:5000/foo")
  end
end
