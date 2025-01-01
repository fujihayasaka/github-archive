# frozen_string_literal: true

require "test_helper"

class ApplicationImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def test_importer(attributes: nil, count: 2)
    importer =
      Class.new(ApplicationImporter) do
        def self.source
          "munger"
        end

        cattr_accessor :attributes

        def each(&)
          self.class.attributes.each(&)
        end
      end
    attributes ||= Array.new(count) { FactoryBot.attributes_for(:feed_entry, source: "munger") }
    importer.attributes = attributes
    importer
  end

  test "fetches a valid importer class" do
    importer = ApplicationImporter.importer_for_source("nvd") # valid

    assert_equal NVDImporter, importer
  end

  test "will not fetch an invalid importer class" do
    assert_raise ArgumentError do
      ApplicationImporter.importer_for_source("bogus") # invalid
    end
  end

  test "creates an import record" do
    importer = test_importer(count: 3)

    assert_difference -> { Import.count }, 1 do
      importer.import
    end

    import = Import.order(:id).last
    assert_equal "munger", import.source
    refute_nil import.started_at
    assert_equal 3, import.total_count
    assert_equal 3, import.created_count
    assert_equal 0, import.updated_count
    assert_equal 0, import.errored_count
    refute_nil import.finished_at
  end

  test "creates new feed entry records" do
    importer = test_importer(count: 3)

    assert_difference -> { FeedEntry.count }, 3 do
      importer.import
    end
  end

  test "updates existing feed entry records" do
    importer = test_importer(count: 3)
    create(:feed_entry, :resolved, importer.attributes[1])

    assert_difference -> { FeedEntry.count }, 2 do
      importer.import
    end

    import = Import.order(:id).last
    assert_equal 3, import.total_count
    assert_equal 2, import.created_count
    assert_equal 1, import.updated_count
    assert_equal 0, import.errored_count
  end

  test "enqueues resolution of created feed entries" do
    importer = test_importer(count: 3)

    importer.import

    feed_entries = FeedEntry.order(:id).last(3)
    assert feed_entries.all?(&:unresolved?), "should all be unresolved"
    assert_equal(3, enqueued_jobs.count { |j| j[:job] == ResolveFeedEntryJob })
  end

  test "enqueues resolution of significantly updated feed entries" do
    importer = test_importer(count: 3)
    # Create feed entries that behave as if they have significant updates.
    FeedEntry.any_instance.stubs(:previous_changes_significant?).returns(true)
    feed_entries = Array.new(3) do |i|
      create(:feed_entry, :resolved, importer.attributes[i])
    end

    importer.import

    feed_entries.each(&:reload)
    assert feed_entries.all?(&:unresolved?), "should all be unresolved"
    assert_equal(3, enqueued_jobs.count { |j| j[:job] == ResolveFeedEntryJob })
  end

  test "skips resolution for insignificant updates" do
    importer = test_importer(count: 3)
    # Create feed entries that behave as if they have insignificant updates.
    FeedEntry.any_instance.stubs(:previous_changes_significant?).returns(false)
    feed_entries = Array.new(3) do |i|
      create(:feed_entry, :resolved, importer.attributes[i])
    end

    importer.import

    feed_entries.each(&:reload)
    assert feed_entries.all?(&:resolved?), "should all still be resolved"
    assert_equal(0, enqueued_jobs.count { |j| j[:job] == ResolveFeedEntryJob })
  end

  # use `limit` arg for setting a test repo up, without pulling all the NVD feed entries
  test "supports a limit arg which limits how many feed entries are imported" do
    importer = test_importer(count: 5)

    assert_difference -> { FeedEntry.count }, 2 do
      importer.import(limit: 2)
    end
  end

  test "tracks who requested the import" do
    assert_nil PaperTrail.request.whodunnit
    tracked_importer = test_importer(count: 3)
    untracked_importer = test_importer(count: 3)
    feed_entries = FeedEntry.order(:id)

    assert_changes -> { FeedEntry.count }, from: 0, to: 3 do
      tracked_importer.import
    end

    feed_entries.first(3).each do |untracked_feed_entry|
      assert_nil untracked_feed_entry.paper_trail.originator
    end

    PaperTrail.request(whodunnit: "nat") do
      assert_changes -> { FeedEntry.count }, from: 3, to: 6 do
        untracked_importer.import
      end

      feed_entries.last(3).each do |tracked_feed_entry|
        assert_equal "nat", tracked_feed_entry.paper_trail.originator
      end
    end
  end

  test "auto_import" do
    # can be disabled in class definition
    no_auto_import_importer = Class.new(ApplicationImporter) do
      disable_auto_import
    end
    refute no_auto_import_importer.auto_import?

    # auto import is the default
    auto_import_importer = Class.new(ApplicationImporter)
    assert auto_import_importer.auto_import?
  end

  test "enqueues a MonitorImportForSlackJob when report_to_slack is true" do
    importer = test_importer(count: 2)

    assert_enqueued_with(job: MonitorImportForSlackJob) do
      importer.import report_to_slack: true
    end
  end

  test "does not enqueue a MonitorImportForSlackJob when report_to_slack is false" do
    importer = test_importer(count: 2)

    assert_no_enqueued_jobs(only: MonitorImportForSlackJob) do
      importer.import report_to_slack: false
    end
  end
end
