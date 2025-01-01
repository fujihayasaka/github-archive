# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryPackageUrlTest < GitHub::TestCase
  def setup
    @advisory_package_url = AdvisoryPackageUrl.new("rubygems", "rails")
    AdvisoryDBToolkit::PackageUrlObtainer.stubs(:get_url).returns("https://example.com/ruby/rails")
  end

  context "#get_url" do
    test "get_url returns the correct URL" do
      url = @advisory_package_url.get_url
      assert_equal "https://example.com/ruby/rails", url
    end

    test "get_url returns nil if ecosystem is not supported" do
      @advisory_package_url = AdvisoryPackageUrl.new("OtherEcosys", "test")
      url = @advisory_package_url.get_url
      assert_nil url
    end

    test "get_url returns nil if package name is blank" do
      @advisory_package_url = AdvisoryPackageUrl.new("rubygems", "")
      url = @advisory_package_url.get_url
      assert_nil url
    end

    test "fetch_package_url returns the correct URL" do
      url = @advisory_package_url.send(:fetch_package_url)
      assert_equal "https://example.com/ruby/rails", url
    end

    test "fetch_package_url returns nil if fails" do
      error = -> { raise StandardError.new("Failed getting URL") }
      AdvisoryDBToolkit::PackageUrlObtainer.stubs(:get_url).raises(error)

      url = assert_nothing_raised do
        @advisory_package_url.send(:fetch_package_url)
      end
      assert_nil url
    end

    test "get package URL from cache if present" do
      package_url = "https://example.com/ruby/rails"
      GitHub.cache.expects(:fetch).returns(package_url)

      AdvisoryDBToolkit::PackageUrlObtainer.expects(:fetch_package_url).never

      url = @advisory_package_url.get_url
      assert_equal package_url, url
    end

  end

  context "#supported_ecosystem?" do
    test "supported_ecosystem? returns true if ecosystem is supported" do
      supported = @advisory_package_url.supported_ecosystem?
      assert supported
    end

    test "supported_ecosystem? returns false if ecosystem is not supported" do
      @advisory_package_url = AdvisoryPackageUrl.new("OtherEcosys", "test")
      supported = @advisory_package_url.supported_ecosystem?
      refute supported
    end

    test "returns false if ecosystem is nil" do
      @advisory_package_url = AdvisoryPackageUrl.new(nil, "test")
      supported = @advisory_package_url.supported_ecosystem?
      refute supported
    end

    test "returns false if package is nil" do
      @advisory_package_url = AdvisoryPackageUrl.new("OtherEcosys", nil)
      supported = @advisory_package_url.supported_ecosystem?
      refute supported
    end
  end

  test "ecosystem_package_cache_key returns the correct cache key" do
    cache_key = @advisory_package_url.send(:ecosystem_package_cache_key)
    assert_equal "ecosystem_package_url:test:rubygems:rails", cache_key
  end
end
