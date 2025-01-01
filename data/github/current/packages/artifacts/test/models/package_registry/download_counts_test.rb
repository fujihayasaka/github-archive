# typed: true
# frozen_string_literal: true

require "test_helper"

class PackageRegistry::DownloadCountsTest < GitHub::TestCase
  context "Null" do
    test "#total" do
      subject = PackageRegistry::DownloadCounts::NULL
      assert_equal 0, subject.total
    end

    test "#day_counts" do
      subject = PackageRegistry::DownloadCounts::NULL
      assert_equal 30, subject.day_counts.length
      assert_equal 0, subject.day_counts.sum
    end

    test "#today" do
      subject = PackageRegistry::DownloadCounts::NULL
      assert_equal 0, subject.today
    end

    test "#last_week" do
      subject = PackageRegistry::DownloadCounts::NULL
      assert_equal 0, subject.last_week
    end

    test "#last_30" do
      subject = PackageRegistry::DownloadCounts::NULL
      assert_equal 0, subject.last_30
    end
  end

  context "with data" do
    test "#today" do
      raw = stub(total: 10_000, day_counts: [14, 6, 17, 2, 18, 8, 1, 3, 6, 13, 7, 11, 2, 12, 9, 0, 2, 3, 10, 12, 14, 9, 3, 16, 18, 0, 17, 17, 14, 11])
      subject = PackageRegistry::DownloadCounts.new(raw)
      assert_equal 14, subject.today
    end

    test "#last_week" do
      raw = stub(total: 10_000, day_counts: [14, 6, 17, 2, 18, 8, 1, 3, 6, 13, 7, 11, 2, 12, 9, 0, 2, 3, 10, 12, 14, 9, 3, 16, 18, 0, 17, 17, 14, 11])
      subject = PackageRegistry::DownloadCounts.new(raw)
      assert_equal 66, subject.last_week
    end

    test "#last_30" do
      raw = stub(total: 10_000, day_counts: [14, 6, 17, 2, 18, 8, 1, 3, 6, 13, 7, 11, 2, 12, 9, 0, 2, 3, 10, 12, 14, 9, 3, 16, 18, 0, 17, 17, 14, 11])
      subject = PackageRegistry::DownloadCounts.new(raw)
      assert_equal 275, subject.last_30
    end
  end
end
