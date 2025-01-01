# frozen_string_literal: true

require "test_helper"

class GitHubRepoImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Using pypa as sample data for a github repo hosted advisory database
  GitHubRepoImporter.const_set(:REPO_NWO, "pypa/advisory-database")
  GitHubRepoImporter.const_set(:ADVISORY_FOLDER, "vulns/")
  setup do
    @importer = GitHubRepoImporter.new
    @importer.stubs(:source).returns("pypa_advisory")
  end

  test "retrieve_current_advisory_paths fetches all paths from the current tree" do
    VCR.use_cassette("pypa_all_files") do
      files = @importer.retrieve_current_advisory_paths

      assert files.include?("vulns/linotp/PYSEC-2019-103.yaml")
    end

    WebMock.assert_requested(
      :get,
      "https://api.github.com/repos/pypa/advisory-database/commits/main",
      times: 1,
    )

    WebMock.assert_requested(
      :get,
      Regexp.new("https://api.github.com/repos/pypa/advisory-database/git/trees/.+?recursive=true"),
      times: 1,
    )
  end

  test "retrieve_updated_advisory_paths returns empty when no previous bulk import" do
    @importer.retrieve_updated_advisory_paths
    WebMock.assert_not_requested(
      :get,
      "https://api.github.com/repos/pypa/advisory-database/commits?path=vulns/&since=2022-03-16T00:00:00%2B00:00",
    )
  end

  test "retrieve_updated_advisory_paths fetches recent commits when previous bulk import" do
    create(:import, source: "pypa_advisory", started_at: "2022-03-16", finished_at: "2022-03-16", bulk: true)

    VCR.use_cassette("pypa_updated_files") do
      @importer.retrieve_updated_advisory_paths
    end

    WebMock.assert_requested(
      :get,
      "https://api.github.com/repos/pypa/advisory-database/commits?path=vulns/&since=2022-03-16T00:00:00%2B00:00",
      times: 1,
    )
  end

  test "retrieve_updated_advisory_paths translates commits into updated advisory file paths" do
    create(:import, source: "pypa_advisory", started_at: "2022-03-16", finished_at: "2022-03-16", bulk: true)

    VCR.use_cassette("pypa_updated_files") do
      files = @importer.retrieve_updated_advisory_paths

      assert files.include?("vulns/lin-cms/PYSEC-2021-339.yaml")
      assert_equal files.count, files.uniq.count
      assert(files.all? { |file| file.starts_with?("vulns/") })
    end
  end

  test "advisory_paths defaults to updated" do
    create(:import, source: "pypa_advisory", started_at: "2022-03-16", finished_at: "2022-03-16", bulk: true)

    VCR.use_cassette("pypa_updated_files") do
      files = @importer.advisory_paths
      assert_equal 8, files.count
    end

    VCR.use_cassette("pypa_all_files") do
      @importer.instance_variable_set(:@backfill, true)
      files = @importer.advisory_paths
      assert_equal 2072, files.count
    end
  end
end
