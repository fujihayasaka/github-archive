require "fake_fjord_sink_server"
require "fake_nuget_server"
require_relative "../lib/nuget_catalog"
require_relative "../lib/nuget_importer"

class IntegrationTest < Minitest::Test
  CHECKPOINT_NAME = "nuget_import"

  def setup
    @sink_server = FakeFjordSinkServer.new
    @sink_server.start
    @sink = Nuget::FjordSink.new(fjord_url: @sink_server.url, checkpoints_url: @sink_server.url)
    @nuget_server = FakeNugetServer.new
    @nuget_server.start
    @catalog = Nuget::Catalog.new(host: @nuget_server.address)
  end

  def test_full_import
    setup
    importer = Nuget::Importer.new(fjord_sink: @sink, catalog: @catalog)
    importer.process_pages

    # processes all 3 pages which have 5 packages in total
    assert_equal 5, @sink_server.package_releases.count

    # expect current checkpoint to be that of last page; page 2 processed
    assert_equal @sink_server.checkpoints["nuget_import"], 1422773455
    teardown
  end

  def test_incremental_import
    setup
    importer = Nuget::Importer.new(fjord_sink: @sink, catalog: @catalog)

    # sets checkpoint to timestamp of page 1, thus we should process only page 2
    importer.set_checkpoint("2015-02-01T06:39:53.9553899Z")

    importer.process_pages

    # page 2 has only 1 package, so expect package releases to be 1
    assert_equal 1, @sink_server.package_releases.count

    assert_equal @sink_server.checkpoints["nuget_import"], 1422773455
    teardown
  end

  def test_nothing_to_import
    setup
    importer = Nuget::Importer.new(fjord_sink: @sink, catalog: @catalog)

    # set checkpoint to commitTimestamp of last processed page
    importer.set_checkpoint("2015-02-01T06:58:47.9532886Z")

    # check to see if there are new pages to process
    importer.process_pages

    # Since, there has been no change/update, expect package releases to be 0
    assert_equal 0, @sink_server.package_releases.count

    # make sure last saved chekpoint is still one of last processed page
    assert_equal @sink_server.checkpoints["nuget_import"], 1422773927

    teardown
  end

  def teardown
    @sink_server.close
    @nuget_server.close
  end
end
