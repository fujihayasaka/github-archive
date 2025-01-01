# typed: true
# frozen_string_literal: true

# A collection of DeprecatedPullRequestReviewThreads or CommitCommentThreads,
# responsible for grouping comments into threads and navigating from
# a path to a line position.
#
# Behaves like an Array of threads with extra indexed lookups for paths
# and line positions.
#
# Examples
#
#   threads = ReviewThreads.new([pull_request_review_thread])
#
#   readme = threads.path("README")
#   # => ReviewThreads
#
#   line42 = readme.position(42)
#   # => ReviewThreads
#
#   line42.each do |thread|
#     thread.comments.each do |comment|
#       # Render comment html.
#     end
#   end
#
#  # Or a quick one-liner
#  threads.path("README").position(42)
class ReviewThreads
  include Enumerable

  attr_reader :threads

  def initialize(threads)
    @threads = threads
  end

  # Retrieve the, possibly empty, collection of threads for this path name.
  #
  # Returns a ReviewThreads collection.
  def path(path)
    ReviewThreads.new(paths[path] || [])
  end

  # Retrieve the, possibly empty, collection of threads at this line number.
  #
  # Returns a ReviewThreads collection.
  def position(position)
    ReviewThreads.new(positions[position] || [])
  end

  # Iterate through each DeprecatedPullRequestReviewThread in the collection.
  #
  # Returns an Enumerator.
  def each(&block)
    @threads.each(&block)
  end

  # Iterate through each (path, ReviewThreads) pair.
  #
  # Examples
  #
  #   # Group threads into file paths.
  #   threads.each_path do |path, threads_at_path|
  #
  #     # Group threads on a path into their diff positions.
  #     threads_at_path.each_position do |position, threads_at_position|
  #
  #       # Process each comment thread at this position.
  #       threads_at_position.each do |thread|
  #
  #         thread.comments do |comment|
  #           # => PullRequestReviewComment
  #         end
  #       end
  #     end
  #   end
  #
  # Returns an Enumerator.
  def each_path(&block)
    paths.keys.map { |name| [name, path(name)] }.each(&block)
  end

  # Iterate through each (position, ReviewThreads) pair.
  #
  # Returns an Enumerator.
  def each_position(&block)
    positions.keys.sort.map { |ix| [ix, position(ix)] }.each(&block)
  end

  def empty?
    @threads.empty?
  end

  def size
    @threads.size
  end

  def first
    @threads.first
  end

  def last
    @threads.last
  end

  def outdated
    # TODO once we transitioned to the PRRC#outdated? attribute, use it here
    @threads.select { |thread| !thread.live? }
  end

  def sorted
    ReviewThreads.new(@threads.sort_by do |thread|
      [thread.path, thread.position, thread.created_at, thread.id]
    end)
  end

  def position_for_thread_id(thread_id)
    @threads.detect { |thread| thread.pull_request_review_thread_id == thread_id }&.position
  end

  private

  def paths
    @paths ||= @threads.group_by { |thread| thread.path }
  end

  def positions
    @positions ||= @threads.group_by { |thread| thread.position }
  end
end
