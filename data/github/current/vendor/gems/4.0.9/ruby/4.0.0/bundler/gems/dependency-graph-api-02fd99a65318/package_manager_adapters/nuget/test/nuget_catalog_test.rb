require "fake_fjord_sink_server"
require "fake_nuget_server"
require_relative "../lib/nuget_catalog"

class NugetCatalogTest < Minitest::Test

  def setup
    @sink_server = FakeFjordSinkServer.new
    @sink_server.start
    @sink = Nuget::FjordSink.new(fjord_url: @sink_server.url, checkpoints_url: @sink_server.url)
    @nuget_server = FakeNugetServer.new
    @nuget_server.start
    @catalog = Nuget::Catalog.new(host: @nuget_server.address)
  end

  def test_load_page_raises_argument_error_on_nil_url
    assert_raises ArgumentError do
      @catalog.load_page(nil)
    end
  end

  def test_load_page_returns_a_hash
    assert_instance_of(Hash, @catalog.load_page("#{@nuget_server.address}/v3/catalog0/page1.json"))
  end

  def test_load_page_returns_nil_if_given_bad_url
    assert_nil @catalog.load_page("https://")
  end


  def test_find_page_and_process_packages_returns_package_hashes
    @catalog.find_page_and_process_packages("#{@nuget_server.address}/v3/catalog0/page1.json") do |package|
      assert_instance_of(Hash, package)
    end
  end

  def test_find_page_and_process_packages_raises_argument_error_on_nil_url
    assert_raises ArgumentError do
      @catalog.find_page_and_process_packages(nil)
    end
  end

  def test_find_page_and_process_packages_raises_argument_error_when_no_block_given
    assert_raises ArgumentError do
      @catalog.find_page_and_process_packages("#{@nuget_server.address}/v3/catalog0/page0.json")
    end
  end

  def teardown
    @sink_server.close
    @nuget_server.close
  end
end
