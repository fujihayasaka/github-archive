require "fake_fjord_sink_server"
require_relative "vcr_setup"
require_relative "../lib/cargo_snapshot"

class CargoSnapshotTest < Minitest::Test
  def setup
    @fjord_sink_server = FakeFjordSinkServer.new
    @fjord_sink_server.start
    @fjord_sink = Cargo::FjordSink.new(fjord_url: @fjord_sink_server.url, checkpoints_url: @fjord_sink_server.url)
  end

  def teardown
    @fjord_sink_server.close
  end

  def test_import_registry_snapshot
      stub_registry_snapshot_cargo_importer do |importer|
        importer.import_registry_snapshot

        releases = @fjord_sink_server.package_releases.map { |r| JSON.parse(r["value"]) }

        assert_equal 6, releases.count
        assert_equal 3, releases.count { |r| r["package_name"] == "itoa" }
        assert_equal 2, releases.count { |r| r["package_name"] == "any_ascii" }
        assert_equal 1, releases.count { |r| r["package_name"] == "cargo-fancy" }

        itoa46 = releases.find { |r| r["package_name"] == "itoa" && r["package_version"] == "0.4.6" }
        assert_equal "rust", itoa46["package_manager"]
        assert_equal 9990507, itoa46["download_count"]
        assert_equal 1592332264, itoa46["published_at"]
        assert_equal "MIT OR Apache-2.0", itoa46["license"]
        assert_equal "https://github.com/dtolnay/itoa", itoa46["source_url"]
        assert_equal "https://docs.rs/itoa", itoa46["docs_url"]

        any031 = releases.find { |r| r["package_name"] == "any_ascii" && r["package_version"] == "0.3.1" }
        assert_equal "rust", any031["package_manager"]
        assert_equal 531, any031["download_count"]
        assert_equal 1649237235, any031["published_at"]
        assert_equal "https://github.com/anyascii/anyascii", any031["source_url"]
        assert_equal "https://anyascii.com", any031["home_url"]

        cf = releases.find { |r| r["package_name"] == "cargo-fancy" && r["package_version"] == "0.1.0" }
        assert_equal "rust", cf["package_manager"]
        assert_equal 1056, cf["download_count"]
        assert_equal 1512009736, cf["published_at"]
        assert_equal "https://github.com/alexcrichton/cargo-fancy", cf["source_url"]
        assert_equal "https://github.com/alexcrichton/cargo-fancy", cf["home_url"]

        assert_equal 2, cf["dependencies"].count
        cf_foo_dep =  cf["dependencies"].find { |d| d["package_name"] == "foo" }
        assert_equal ">= 0.4.0, < 0.5.0", cf_foo_dep["requirements"]
        assert_equal "runtime", cf_foo_dep["scope"]
      end
  end

  private

  # Wrap the Cargo::Snapshot and stub the input files to set up
  # a proper e2e snapshot ingest test using fixtures as inputs
  def stub_registry_snapshot_cargo_importer(&block)
    importer = Cargo::Snapshot.new(fjord_sink: @fjord_sink)

    importer.stub :download_hydrate_registry_snapshot, "" do
      importer.stub :resolve_crates_csv_file, "test/snapshot_fixtures/crates.csv" do
        importer.stub :resolve_versions_csv_file, "test/snapshot_fixtures/versions.csv" do
          importer.stub :resolve_dependencies_csv_file, "test/snapshot_fixtures/dependencies.csv" do
            importer.stub :resolve_metadata_json_file, "test/snapshot_fixtures/metadata.json" do
              block.call(importer)
            end
          end
        end
      end
    end
  end
end
