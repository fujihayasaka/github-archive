require "minitest/stub_const"

require_relative "fake_fjord_sink_server"
require_relative "vcr_setup"
require_relative "../lib/pub_api"

class PubApiTest < Minitest::Test
  def setup
    @fjord_sink_server = FakeFjordSinkServer.new
    @fjord_sink_server.start
    @fjord_sink = Pub::FjordSink.new(fjord_url: @fjord_sink_server.url, checkpoints_url: @fjord_sink_server.url)
  end

  def teardown
    @fjord_sink_server.close
  end

   def test_single_package_all_versions_import
     VCR.use_cassette("mineral-single-package") do
       importer = Pub::Api.new(fjord_sink: @fjord_sink)
       importer.import_package_releases(target_package: "mineral", all_versions: true)

       assert_equal 11, @fjord_sink_server.package_releases.count

       release100 = fjord_next_release

       assert_equal "pub", release100["package_manager"]
       assert_equal "mineral", release100["package_name"]
       assert_equal "1.0.0", release100["package_version"]
       assert_equal "https://github.com/mineral-dart/core", release100["source_url"]
       assert_nil release100["docs_url"]
       assert_nil release100["home_url"]
       assert_equal 1662834813, release100["published_at"]

       deps100 = release100["dependencies"]
       assert_equal 5, deps100.count

       args100 = deps100.find { |d| d["package_name"] == "args" }
       assert_equal "args", args100["package_name"]
       assert_equal "runtime", args100["scope"]
       assert_equal ">= 2.3.1, < 3.0.0", args100["requirements"]

       path100 = deps100.find { |d| d["package_name"] == "path" }
       assert_equal "path", path100["package_name"]
       assert_equal "runtime", path100["scope"]
       assert_equal ">= 1.8.2, < 2.0.0", path100["requirements"]

       http100 = deps100.find { |d| d["package_name"] == "http" }
       assert_equal "http", http100["package_name"]
       assert_equal "runtime", http100["scope"]
       assert_equal ">= 0.13.4, < 0.14.0", http100["requirements"]

       interact100 = deps100.find { |d| d["package_name"] == "interact" }
       assert_equal "interact", interact100["package_name"]
       assert_equal "runtime", interact100["scope"]
       assert_equal ">= 2.1.1, < 3.0.0", interact100["requirements"]

       collection100 = deps100.find { |d| d["package_name"] == "collection" }
       assert_equal "collection", collection100["package_name"]
       assert_equal "runtime", collection100["scope"]
       assert_equal ">= 1.16.0, < 2.0.0", collection100["requirements"]

       release101 = fjord_next_release

       assert_equal "pub", release101["package_manager"]
       assert_equal "mineral", release101["package_name"]
       assert_equal "1.0.1", release101["package_version"]
       assert_equal "https://github.com/mineral-dart/core", release101["source_url"]
       assert_nil release101["docs_url"]
       assert_nil release101["home_url"]
       assert_equal 1662835863, release101["published_at"]

       deps101 = release101["dependencies"]
       assert_equal 5, deps101.count
       assert_equal "args", deps101.first["package_name"]
       assert_equal "runtime", deps101.first["scope"]
       assert_equal ">= 2.3.1, < 3.0.0", deps101.first["requirements"]
     end
   end

   def test_single_package_single_version_import
     VCR.use_cassette("mineral-single-package") do
       importer = Pub::Api.new(fjord_sink: @fjord_sink)
       importer.import_package_releases(target_package: "mineral", target_versions: ["1.0.7"])

       assert_equal 1, @fjord_sink_server.package_releases.count

       release107 = fjord_next_release

       assert_equal "pub", release107["package_manager"]
       assert_equal "mineral", release107["package_name"]
       assert_equal "1.0.7", release107["package_version"]
       assert_equal "https://github.com/mineral-dart/core", release107["source_url"]
       assert_nil release107["docs_url"]
       assert_nil release107["home_url"]
       assert_equal 1662901768, release107["published_at"]

       deps107 = release107["dependencies"]
       assert_equal 5, deps107.count

       args107 = deps107.find { |d| d["package_name"] == "args" }
       assert_equal "args", args107["package_name"]
       assert_equal "runtime", args107["scope"]
       assert_equal ">= 2.3.1, < 3.0.0", args107["requirements"]

       path107 = deps107.find { |d| d["package_name"] == "path" }
       assert_equal "path", path107["package_name"]
       assert_equal "runtime", path107["scope"]
       assert_equal ">= 1.8.2, < 2.0.0", path107["requirements"]

       http107 = deps107.find { |d| d["package_name"] == "http" }
       assert_equal "http", http107["package_name"]
       assert_equal "runtime", http107["scope"]
       assert_equal ">= 0.13.4, < 0.14.0", http107["requirements"]

       interact107 = deps107.find { |d| d["package_name"] == "interact" }
       assert_equal "interact", interact107["package_name"]
       assert_equal "runtime", interact107["scope"]
       assert_equal ">= 2.1.1, < 3.0.0", interact107["requirements"]

       collection107 = deps107.find { |d| d["package_name"] == "collection" }
       assert_equal "collection", collection107["package_name"]
       assert_equal "runtime", collection107["scope"]
       assert_equal ">= 1.16.0, < 2.0.0", collection107["requirements"]
     end
   end

   def test_most_popular_packages
     VCR.use_cassette("most-popular-packages") do
       importer = Pub::Api.new(fjord_sink: @fjord_sink)

       # limit this test to 2 pages to accomodate the corresponding
       # VCR cassette data import_most_popular will consume
       Pub::Api.stub_const("PUB_API_POPULAR_MAX_PAGES", 2) do
         importer.import_most_popular
       end

       releases = fjord_all_releases
       assert_equal releases.count, 25

       state_extended_releases = releases.select { |p| p["package_name"] == "state_extended" }
       assert_equal 11, state_extended_releases.count

       se020 = state_extended_releases.first
       assert_equal "pub", se020["package_manager"]
       assert_equal "state_extended", se020["package_name"]
       assert_equal "0.2.0", se020["package_version"]
       assert_equal "https://github.com/AndriousSolutions/state_extended", se020["source_url"]
       assert_nil se020["docs_url"]
       assert_equal "https://www.andrioussolutions.com", se020["home_url"]
       assert_equal 1657499724, se020["published_at"]
       assert_equal 1, se020["dependencies"].count

       se110 = state_extended_releases.last
       assert_equal "pub", se110["package_manager"]
       assert_equal "state_extended", se110["package_name"]
       assert_equal "1.1.0", se110["package_version"]
       assert_equal "https://github.com/AndriousSolutions/state_extended", se110["source_url"]
       assert_nil se110["docs_url"]
       assert_equal "https://www.andrioussolutions.com", se110["home_url"]
       assert_equal 1663351630, se110["published_at"]
       assert_equal 1, se110["dependencies"].count

       calendar_day_view_releases = releases.select { |p| p["package_name"] == "calendar_day_view" }
       assert_equal 2, calendar_day_view_releases.count

       cdv100 = calendar_day_view_releases.first
       assert_equal "pub", cdv100["package_manager"]
       assert_equal "calendar_day_view", cdv100["package_name"]
       assert_equal "1.0.0", cdv100["package_version"]
       assert_equal "https://github.com/samderlust/calendar_day_view", cdv100["source_url"]
       assert_nil cdv100["docs_url"]
       assert_equal "https://github.com/samderlust/calendar_day_view", cdv100["home_url"]
       assert_equal 1663351508, cdv100["published_at"]
       assert_empty cdv100["dependencies"]

       cdv101 = calendar_day_view_releases.last
       assert_equal "pub", cdv101["package_manager"]
       assert_equal "calendar_day_view", cdv101["package_name"]
       assert_equal "1.0.1", cdv101["package_version"]
       assert_equal "https://github.com/samderlust/calendar_day_view", cdv101["source_url"]
       assert_nil cdv101["docs_url"]
       assert_equal "https://github.com/samderlust/calendar_day_view", cdv101["home_url"]
       assert_equal 1663352380, cdv101["published_at"]
       assert_empty cdv101["dependencies"]

       app_version_update_releases = releases.select { |r| r["package_name"] == "app_version_update" }
       assert_equal 12, app_version_update_releases.count

       avu001 = app_version_update_releases.first
       assert_equal "pub", avu001["package_manager"]
       assert_equal "app_version_update", avu001["package_name"]
       assert_equal "0.0.1", avu001["package_version"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu001["source_url"]
       assert_nil avu001["docs_url"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu001["home_url"]
       assert_equal 1663265876, avu001["published_at"]
       assert_empty avu001["dependencies"]

       avu033 = app_version_update_releases.last
       assert_equal "pub", avu033["package_manager"]
       assert_equal "app_version_update", avu033["package_name"]
       assert_equal "0.3.3", avu033["package_version"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu033["source_url"]
       assert_nil avu033["docs_url"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu033["home_url"]
       assert_equal 1663352097, avu033["published_at"]
       assert_empty avu033["dependencies"]

       # the new checkpoint should be the most recent "latest" package
       # release "published" timestamp we saw in this run
       raw_checkpoint = importer.get_checkpoint(Pub::PUB_CHECKPOINT)
       new_checkpoint = Time.at(raw_checkpoint).to_datetime
       assert_equal DateTime.parse("2022-09-16T18:19:40Z"), new_checkpoint
     end
   end

   def test_most_popular_packages_resume_job
     VCR.use_cassette("most-popular-packages-resumed") do
       importer = Pub::Api.new(fjord_sink: @fjord_sink)

       # limit this test to 2 pages to accomodate the corresponding
       # VCR cassette data import_most_popular will consume
       Pub::Api.stub_const("PUB_API_POPULAR_MAX_PAGES", 2) do
         # resume the job from page 2, as if it was interrupted!
         importer.import_most_popular(from_page: 2)
       end

       # expectation: only page 2 of most popular packages will be present
       releases = fjord_all_releases
       assert_equal releases.count, 12

       app_version_update_releases = releases.select { |r| r["package_name"] == "app_version_update" }
       assert_equal 12, app_version_update_releases.count

       avu001 = app_version_update_releases.first
       assert_equal "pub", avu001["package_manager"]
       assert_equal "app_version_update", avu001["package_name"]
       assert_equal "0.0.1", avu001["package_version"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu001["source_url"]
       assert_nil avu001["docs_url"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu001["home_url"]
       assert_equal 1663265876, avu001["published_at"]
       assert_empty avu001["dependencies"]

       avu033 = app_version_update_releases.last
       assert_equal "pub", avu033["package_manager"]
       assert_equal "app_version_update", avu033["package_name"]
       assert_equal "0.3.3", avu033["package_version"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu033["source_url"]
       assert_nil avu033["docs_url"]
       assert_equal "https://github.com/kauemurakami/app_version_update", avu033["home_url"]
       assert_equal 1663352097, avu033["published_at"]
       assert_empty avu033["dependencies"]

       # the new checkpoint should be the most recent "latest" package
       # release "published" timestamp we saw in this run. this is not
       # super important since the initial most-recent-updated run
       # will reset this
       raw_checkpoint = importer.get_checkpoint(Pub::PUB_CHECKPOINT)
       new_checkpoint = Time.at(raw_checkpoint).to_datetime
       assert_equal DateTime.parse("2022-09-16T18:14:57Z"), new_checkpoint
     end
   end



  def test_latest_packages_update_with_older_checkpoint
    VCR.use_cassette("updated-packages") do
      importer = Pub::Api.new(fjord_sink: @fjord_sink)

      # due to the data shape of the Pub updates API vs. package
      # details API, and a desire to minimize API calls, we will
      # (re)publish all releases for all packages, up to and
      # including the first package bearing a "latest" release
      # published prior to the current checkpoint.
      previous_checkpoint = DateTime.parse("2022-09-15T21:00:00.000Z")
      importer.set_checkpoint(Pub::PUB_CHECKPOINT, previous_checkpoint)

      importer.import_latest_releases

      releases = fjord_all_releases
      assert_equal 60, releases.count

       go_router_releases = releases.select { |p| p["package_name"] == "go_router_builder" }
       assert_equal 13, go_router_releases.count

       gr100 = go_router_releases.first
       assert_equal "pub", gr100["package_manager"]
       assert_equal "go_router_builder", gr100["package_name"]
       assert_equal "1.0.0", gr100["package_version"]
       assert_equal "https://github.com/flutter/packages/tree/main/packages/go_router_builder", gr100["source_url"]
       assert_nil gr100["docs_url"]
       assert_nil gr100["home_url"]
       assert_equal 1651021401, gr100["published_at"]
       assert_equal 10, gr100["dependencies"].count

       gr1012 = go_router_releases.last
       assert_equal "pub", gr1012["package_manager"]
       assert_equal "go_router_builder", gr1012["package_name"]
       assert_equal "1.0.12", gr1012["package_version"]
       assert_equal "https://github.com/flutter/packages/tree/main/packages/go_router_builder", gr1012["source_url"]
       assert_nil gr1012["docs_url"]
       assert_nil gr1012["home_url"]
       assert_equal 1663361817, gr1012["published_at"]
       assert_equal 10, gr1012["dependencies"].count

       xinput_gamepad_releases = releases.select { |p| p["package_name"] == "xinput_gamepad" }
       assert_equal 4, xinput_gamepad_releases.count

       xg008 = xinput_gamepad_releases.first
       assert_equal "pub", xg008["package_manager"]
       assert_equal "xinput_gamepad", xg008["package_name"]
       assert_equal "0.0.8", xg008["package_version"]
       assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg008["source_url"]
       assert_equal "https://github.com/LuanRoger/xinput_gamepad/wiki", xg008["docs_url"]
       assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg008["home_url"]
       assert_equal 1650718123, xg008["published_at"]
       assert_equal 2, xg008["dependencies"].count

       xg120 = xinput_gamepad_releases.last
       assert_equal "pub", xg120["package_manager"]
       assert_equal "xinput_gamepad", xg120["package_name"]
       assert_equal "1.2.0", xg120["package_version"]
       assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg120["source_url"]
       assert_equal "https://github.com/LuanRoger/xinput_gamepad/wiki", xg120["docs_url"]
       assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg120["home_url"]
       assert_equal 1663361461, xg120["published_at"]
       assert_equal 2, xg120["dependencies"].count

       text_indexing_releases = releases.select { |p| p["package_name"] == "text_indexing" }
       assert_equal 28, text_indexing_releases.count

       ti001 = text_indexing_releases.first
       assert_equal "pub", ti001["package_manager"]
       assert_equal "text_indexing", ti001["package_name"]
       assert_equal "0.0.1-beta.1", ti001["package_version"]
       assert_equal "https://github.com/GM-Consult-Pty-Ltd/text_indexing", ti001["source_url"]
       assert_equal "https://github.com/GM-Consult-Pty-Ltd", ti001["home_url"]
       assert_nil ti001["docs_url"]
       assert_equal 1662786183, ti001["published_at"]
       assert_equal 2, ti001["dependencies"].count

       ti070 = text_indexing_releases.last
       assert_equal "pub", ti070["package_manager"]
       assert_equal "text_indexing", ti070["package_name"]
       assert_equal "0.7.0", ti070["package_version"]
       assert_equal "https://github.com/GM-Consult-Pty-Ltd/text_indexing", ti001["source_url"]
       assert_equal "https://github.com/GM-Consult-Pty-Ltd", ti001["home_url"]
       assert_nil ti001["docs_url"]
       assert_equal 1663364935, ti070["published_at"]
       assert_equal 4, ti070["dependencies"].count

       cr_calendar_releases = releases.select { |p| p["package_name"] == "cr_calendar" }
       assert_equal 10, cr_calendar_releases.count

       cc002 = cr_calendar_releases.first
       assert_equal "pub", cc002["package_manager"]
       assert_equal "cr_calendar", cc002["package_name"]
       assert_equal "0.0.2-nullsafety", cc002["package_version"]
       assert_equal "https://github.com/Cleveroad/CRCalendar", cc002["source_url"]
       assert_equal "https://cleveroad.com", cc002["home_url"]
       assert_nil cc002["docs_url"]
       assert_equal 1617956944, cc002["published_at"]
       assert_equal 3, cc002["dependencies"].count

       cc100 = cr_calendar_releases.last
       assert_equal "pub", cc100["package_manager"]
       assert_equal "cr_calendar", cc100["package_name"]
       assert_equal "1.0.0", cc100["package_version"]
       assert_equal "https://github.com/Cleveroad/cr_calendar", cc100["source_url"]
       assert_equal "https://cleveroad.com", cc100["home_url"]
       assert_nil cc100["docs_url"]
       assert_equal 1663321993, cc100["published_at"]
       assert_equal 3, cc100["dependencies"].count

       koala_releases = releases.select { |p| p["package_name"] == "koala" }
       assert_equal 5, koala_releases.count

       k001 = koala_releases.first
       assert_equal "pub", k001["package_manager"]
       assert_equal "koala", k001["package_name"]
       assert_equal "0.0.1", k001["package_version"]
       assert_equal "https://github.com/w2sv/koala", k001["source_url"]
       assert_equal "https://github.com/w2sv/koala", k001["home_url"]
       assert_nil k001["docs_url"]
       assert_equal 1662838174, k001["published_at"]
       assert_equal 3, k001["dependencies"].count

       k011 = koala_releases.last
       assert_equal "pub", k011["package_manager"]
       assert_equal "koala", k011["package_name"]
       assert_equal "0.1.1", k011["package_version"]
       assert_equal "https://github.com/w2sv/koala", k011["source_url"]
       assert_nil k011["home_url"]
       assert_nil k011["docs_url"]
       assert_equal 1663272448, k011["published_at"]
       assert_equal 3, k011["dependencies"].count

      # the new checkpoint should be the most recent "latest" package
      # release "published" timestamp we saw in this run
      raw_checkpoint = importer.get_checkpoint(Pub::PUB_CHECKPOINT)
      new_checkpoint = Time.at(raw_checkpoint).to_datetime
      assert_equal DateTime.parse("2022-09-16T21:48:55Z"), new_checkpoint
    end
  end

  def test_latest_packages_update_from_recent_checkpoint
    VCR.use_cassette("updated-packages") do
      importer = Pub::Api.new(fjord_sink: @fjord_sink)

      # due to the data shape of the Pub updates API vs. package
      # details API, and a desire to minimize API calls, we will
      # (re)publish all releases for all packages, up to and
      # including the first package bearing a "latest" release
      # published prior to the current checkpoint.
      previous_checkpoint = DateTime.parse("2022-09-16T20:55:00Z")
      importer.set_checkpoint(Pub::PUB_CHECKPOINT, previous_checkpoint)

      # with a checkpoint set just BEFORE xinput_gamepad's "published"
      # timestamp, we should only pick up releases for go_router_builder
      # and xinput_gamepad packages before detecting we're past the
      # previous checkpoint.
      importer.import_latest_releases

      releases = fjord_all_releases
      assert_equal 17, releases.count

      go_router_releases = releases.select { |p| p["package_name"] == "go_router_builder" }
      assert_equal 13, go_router_releases.count

      gr100 = go_router_releases.first
      assert_equal "pub", gr100["package_manager"]
      assert_equal "go_router_builder", gr100["package_name"]
      assert_equal "1.0.0", gr100["package_version"]
      assert_equal "https://github.com/flutter/packages/tree/main/packages/go_router_builder", gr100["source_url"]
      assert_nil gr100["docs_url"]
      assert_nil gr100["home_url"]
      assert_equal 1651021401, gr100["published_at"]
      assert_equal 10, gr100["dependencies"].count

      gr1012 = go_router_releases.last
      assert_equal "pub", gr1012["package_manager"]
      assert_equal "go_router_builder", gr1012["package_name"]
      assert_equal "1.0.12", gr1012["package_version"]
      assert_equal "https://github.com/flutter/packages/tree/main/packages/go_router_builder", gr1012["source_url"]
      assert_nil gr1012["docs_url"]
      assert_nil gr1012["home_url"]
      assert_equal 1663361817, gr1012["published_at"]
      assert_equal 10, gr1012["dependencies"].count

      xinput_gamepad_releases = releases.select { |p| p["package_name"] == "xinput_gamepad" }
      assert_equal 4, xinput_gamepad_releases.count

      xg008 = xinput_gamepad_releases.first
      assert_equal "pub", xg008["package_manager"]
      assert_equal "xinput_gamepad", xg008["package_name"]
      assert_equal "0.0.8", xg008["package_version"]
      assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg008["source_url"]
      assert_equal "https://github.com/LuanRoger/xinput_gamepad/wiki", xg008["docs_url"]
      assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg008["home_url"]
      assert_equal 1650718123, xg008["published_at"]
      assert_equal 2, xg008["dependencies"].count

      xg120 = xinput_gamepad_releases.last
      assert_equal "pub", xg120["package_manager"]
      assert_equal "xinput_gamepad", xg120["package_name"]
      assert_equal "1.2.0", xg120["package_version"]
      assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg120["source_url"]
      assert_equal "https://github.com/LuanRoger/xinput_gamepad/wiki", xg120["docs_url"]
      assert_equal "https://github.com/LuanRoger/xinput_gamepad", xg120["home_url"]
      assert_equal 1663361461, xg120["published_at"]
      assert_equal 2, xg120["dependencies"].count

      # IMPORTANT: packages paged from the API in "updated" sort
      # order are NOT always in strict "published" time desc order!
      #
      # Again, Pub.dev leaves us with a painful a choice:
      # 1. minimize duplicated updates when some from prev checkpoint land within the last page in the new run :(
      # 2. check "latest" package ingested timestamp per package not per page, and occasionally miss poorly ordered updates :(
      #
      # ...so far, I'm going with the latter, and hoping between the CD.io job and
      # future releases of the same package forcing us to (re)publish all releases
      # for that package, we'll eventually pick up anything important we miss

      # the new checkpoint should be the most recent "latest" package
      # release "published" timestamp we saw in this run
      raw_checkpoint = importer.get_checkpoint(Pub::PUB_CHECKPOINT)
      new_checkpoint = Time.at(raw_checkpoint).to_datetime
      assert_equal DateTime.parse("2022-09-16T20:56:57Z"), new_checkpoint
    end
  end

  private

  def fjord_next_release
    JSON.parse(@fjord_sink_server.package_releases.shift["value"])
  end

  def fjord_all_releases
    count = @fjord_sink_server.package_releases.count
    (0...count).map { |_| fjord_next_release }.to_a
  end
end
