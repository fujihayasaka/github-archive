require "fake_fjord_sink_server"
require_relative "vcr_setup"
require_relative "../lib/composer_importer"

class ComposerImporterTest < Minitest::Test
  LIST_JSON_CHECKPOINT = "composer_list_json_import"
  RSS_CHECKPOINT =  "composer_rss_import"

  def setup
    @fjord_sink_server = FakeFjordSinkServer.new
    @fjord_sink_server.start
    @fjord_sink = Composer::FjordSink.new(fjord_url: @fjord_sink_server.url, checkpoints_url: @fjord_sink_server.url)
  end

  def test_full_list_json_import
    setup
    VCR.use_cassette("full_list_json_import", allow_playback_repeats: true) do
      importer = Composer::Importer.new(fjord_sink: @fjord_sink)
      importer.import_package_list

      #check number of releases imported from "full" packagist list.json
      assert_equal 34, importer.releases_imported_count

      assert_equal 34, @fjord_sink_server.package_releases.count

      # only 8 packages have been processed from vcr packagist list.json
      assert_equal 8, @fjord_sink_server.checkpoints[LIST_JSON_CHECKPOINT]
    end
    teardown
  end

  def test_latest_releases_from_rss_import
    setup
    VCR.use_cassette("latest_releases_from_rss_import", allow_playback_repeats: true) do
      importer = Composer::Importer.new(fjord_sink: @fjord_sink)
      importer.import_latest_releases

      #check number of releases imported from "latest" (vcr-downloaded) releases rss feed
      assert_equal 10, importer.releases_imported_count

      assert_equal 10, @fjord_sink_server.package_releases.count

      assert_equal 1662054128, @fjord_sink_server.checkpoints[RSS_CHECKPOINT]
    end
    teardown
  end

  def test_no_import
    setup
    VCR.use_cassette("latest_releases_from_rss_import", allow_playback_repeats: true) do
      importer = Composer::Importer.new(fjord_sink: @fjord_sink)

      importer.set_checkpoint(RSS_CHECKPOINT, 1662054128)
      importer.import_latest_releases

      #check no releases were imported (because there's no new releases)
      assert_equal 0, importer.releases_imported_count

      assert_equal 0, @fjord_sink_server.package_releases.count

      assert_equal 1662054128, @fjord_sink_server.checkpoints[RSS_CHECKPOINT]
    end
    teardown
  end

  def teardown
    @fjord_sink_server.close
  end
end
