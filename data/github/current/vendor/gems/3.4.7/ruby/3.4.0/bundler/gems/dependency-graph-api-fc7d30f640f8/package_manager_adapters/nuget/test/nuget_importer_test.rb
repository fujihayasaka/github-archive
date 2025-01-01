require "fake_fjord_sink_server"
require "fake_nuget_server"
require_relative "../lib/nuget_catalog"
require_relative "../lib/nuget_importer"

class NugetImporterTest < Minitest::Test

  def setup
    @sink_server = FakeFjordSinkServer.new
    @sink_server.start
    @sink = Nuget::FjordSink.new(fjord_url: @sink_server.url, checkpoints_url: @sink_server.url)
    @nuget_server = FakeNugetServer.new
    @nuget_server.start
    @catalog = Nuget::Catalog.new(host: @nuget_server.address)
    @importer = Nuget::Importer.new(fjord_sink: @sink, catalog: @catalog)
  end

  def test_find_latest_checkpoint_to_be_nil_if_first_time_run
    assert_nil @importer.find_latest_checkpoint
  end

  def test_find_latest_checkpoint_to_be_an_integer_if_checkpoint_is_in_db
    # set chekpoint based on given timestamp
    timestamp = "2015-02-01T06:30:11.7477681Z"
    @importer.set_checkpoint(timestamp)

    assert_instance_of(Integer, @importer.find_latest_checkpoint)

    # check that timestamp found is same as one set
    assert_equal(@importer.find_latest_checkpoint, Time.parse(timestamp).to_i)
  end

  def test_set_checkpoint_succeeds
    timestamp = "2015-02-01T06:30:11.7477681Z"
    assert_equal(true, @importer.set_checkpoint(timestamp))
  end

  def test_set_checkpoint_fails_if_timestamp_is_nil
      assert_raises ArgumentError do
        @importer.set_checkpoint(nil)
      end
  end

  def test_find_catalog_page_urls_after_timestamp_creates_array_of_page_matches
    assert_instance_of(Array, @importer.find_catalog_page_urls_after_timestamp)
  end

  def test_find_catalog_page_urls_after_timestamp_fails_if_timestamp_not_integer_or_nil
    assert_raises ArgumentError do
      @importer.find_catalog_page_urls_after_timestamp("bad string, not timestamp")
    end
  end

  def test_process_pages_process_packages_of_pages_returns_array
    assert_instance_of(Array, @importer.process_pages)
  end

  def teardown
    @sink_server.close
    @nuget_server.close
  end
end
