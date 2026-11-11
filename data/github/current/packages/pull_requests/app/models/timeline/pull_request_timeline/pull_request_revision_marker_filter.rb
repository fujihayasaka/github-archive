# typed: true
# frozen_string_literal: true

# Internal: Filters revision marker placeholders
class Timeline::PullRequestTimeline::PullRequestRevisionMarkerFilter
  def initialize(marker_placeholders, commit_placeholders, viewer)
    @marker_placeholders = marker_placeholders
    @commit_placeholders = commit_placeholders
    @viewer = viewer
  end

  def async_call
    indexed_marker_placeholders = marker_placeholders.index_by(&:last_seen_commit_oid)

    async_marker_placeholders = sorted_commit_placeholders.each_with_index.map do |commit_placeholder, index|
      marker_placeholder = indexed_marker_placeholders[commit_placeholder.oid]
      next Promise.resolve(nil) if marker_placeholder.nil?

      next_commit_index = index + 1
      next_commit_placeholder = sorted_commit_placeholders[next_commit_index]
      next Promise.resolve(nil) if next_commit_placeholder.nil?

      # We want the marker to be placed just before the next commit
      marker_placeholder.sort_datetimes = next_commit_placeholder.sort_datetimes

      # When the all the following commits were authored by the viewer,
      # we do not show the marker placeholder.
      async_rest_commits_authored_by_viewer?(next_commit_index).then do |author_check|
        marker_placeholder unless author_check
      end
    end

    Promise.all(async_marker_placeholders).then(&:compact)
  end

  private

  attr_reader :marker_placeholders, :commit_placeholders, :viewer

  def async_rest_commits_authored_by_viewer?(index)
    rest_commit_placeholders = sorted_commit_placeholders[index..-1]

    async_commit_authors_for(rest_commit_placeholders).then do |commit_authors|
      commit_authors.all? { |author| author == viewer }
    end
  end

  def async_commit_authors_for(commit_placeholders)
    Promise.all(commit_placeholders.map(&:async_author))
  end

  def sorted_commit_placeholders
    return @sorted_commit_placeholders if defined?(@sorted_commit_placeholders)

    # We have to use a stable sort, which Ruby's default sort is not, in order to prevent misordering commits in some circumstances.
    # See https://github.com/github/github/pull/140854 for a ton of context, or more specifically https://github.com/github/github/pull/140854#issuecomment-615015427
    # and https://github.com/github/github/commit/84b2b509bbd3bdcc28728b84cec223c0a8e84667
    @sorted_commit_placeholders = StableSorter.new(commit_placeholders).sort_by(&:sort_datetimes)
  end
end
