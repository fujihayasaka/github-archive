# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsCopilotDiffsFilterTest < GitHub::TestCase
  class MockDiffEntry
    attr_reader :path, :changes, :binary, :truncated, :skipped

    def initialize(path:, changes: 1, binary: false, truncated: false, skipped: false)
      @path = path
      @changes = changes
      @binary = binary
      @truncated = truncated
      @skipped = skipped
    end

    alias_method :binary?, :binary
    alias_method :truncated?, :truncated
    alias_method :skipped?, :skipped
  end

  def mock_entries(paths, changes: 1, binary: false, truncated: false, skipped: false)
    paths.map do |path|
      MockDiffEntry.new(path:, changes: changes, binary: binary, truncated: truncated, skipped: skipped)
    end
  end

  def assert_subset(superset, subset)
    intersection = superset & subset
    assert_same_elements subset, intersection
  end

  setup do
    @copilot_content_exclusion = %w(**/*.txt this_file.rb)
    @good_entries = mock_entries %w(README.md app/models/user.rb .github/ISSUE_TEMPLATE)
    @excluded_entries = mock_entries %w(.gitignore public/octocat.svg bin/setup)
    @big_entries = mock_entries %w(big_new_file.rb), changes: 401
    @truncated_entries = mock_entries %w(too_big_for_git.rb), changes: 10_000, truncated: true
    @binary_entries = mock_entries %w(public/hubot.png), binary: true
    @copilot_entries = mock_entries %w(files/baz.txt this_file.rb)
    @all_entries = @good_entries + @excluded_entries + @big_entries + @truncated_entries + @binary_entries + @copilot_entries
    @filter = PullRequests::Copilot::DiffsFilter.new diffs: @all_entries, copilot_content_exclusion: @copilot_content_exclusion
  end

  test "filters out unwanted files" do
    assert_subset @all_entries, @good_entries
    assert_subset @all_entries, @excluded_entries
    assert_subset @all_entries, @big_entries
    assert_subset @all_entries, @truncated_entries
    assert_subset @all_entries, @binary_entries
    assert_subset @all_entries, @copilot_entries

    filtered = @filter.to_a

    assert_same_elements @good_entries, filtered
  end

  test "records time to filter" do
    frozen_now = Time.now.utc
    Timecop.freeze frozen_now do
      GitHub.dogstats.expects(:timing_since).with("copilot.prompt.filter_diffs", frozen_now, tags: ["size:#{@all_entries.size}"])

      filtered = @filter.to_a
    end
  end
end
