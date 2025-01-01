# typed: true
# frozen_string_literal: true

class CommitCommentThread
  include GitHub::Relay::GlobalIdentification

  # Find the comment threads on a commit.
  #
  # Returns a ReviewThreads collection.
  def self.review_threads(viewer:, commit:, repository:)
    comments = CommitComment.find_for(viewer, commit, repository, true)
    ReviewThreads.new(group_comments(comments))
  end

  # Public: Convert a flat list of comments into a list of threads.
  #
  # comments - An Array of CommitCommentThread records.
  #
  # Returns an Array of CommitCommentThreads.
  def self.group_comments(comments)
    comments.group_by { |c| [c.repository_id, c.commit_id, c.path, c.position] }.values.map do |comments|
      comments = comments.sort_by(&:created_at)
      first_comment = comments.first
      new(
        repository: first_comment.repository,
        commit_id: first_comment.commit_id,
        path: first_comment.path,
        position: first_comment.position,
        comments: comments,
      )
    end.sort_by(&:created_at)
  end

  attr_reader :repository, :commit_id, :path, :position
  attr_accessor :comments

  # Create a new CommitCommentThread.
  #
  # repository - Repository this commit comment thread belongs to
  # commit_id - oid of the commit that this thread belongs to
  # path - the filename path, can be either a String or nil
  # position - the offset in the diff, can be either an Integer or nil
  def initialize(repository:, commit_id:, path: nil, position: nil, comments: [])
    @repository = repository
    @commit_id = commit_id

    if path.nil? || path.is_a?(String)
      @path = path
    else
      raise TypeError, "expected path to be a String, but was #{path.class}"
    end

    if position.nil? || position.is_a?(Integer)
      @position = position
    else
      raise TypeError, "expected position to be a Integer, but was #{position.class}"
    end

    @comments = comments || []
    @comments.each { |c| c.thread = self }
  end

  def new_record?
    id.nil?
  end

  def id
    first_comment.try(:id)
  end

  def created_at
    first_comment.try(:created_at)
  end

  # See IssueTimeline
  def timeline_sort_by
    [created_at]
  end

  # Returns the children items for the purposes of rendering thread(s) on a timeline -
  # i.e. on PullRequest#show
  #
  # See also IssueTimeline#child_enumerator
  #
  # Returns PullRequestReviewComments or CommitComments
  def timeline_children
    comments
  end

  def locked_for?(user)
    false
  end

  # Returns the number of unique authors in this thread.
  def author_count
    @author_count ||= begin
      authors = Set.new
      @comments.each do |c|
        authors << c.user
      end
      authors.size
    end
  end

  def old_style_review_thread?
    comments.first && comments.first.pull_request_review_id.nil?
  end

  def comments_for(viewer)
    comments
  end

  # TODO: Not exposed on DeprecatedPullRequestReviewThread. See if we can get rid of this.
  def line
    first_comment.try(:line)
  end

  # Public: Provide repository attribute via a Promise
  #
  # Returns a Promise
  def async_repository
    Promise.resolve(repository)
  end

  # Public: Global ID for this commit comment thread
  #
  # Returns String
  def global_id
    self.class.global_id_for(repository.id, commit_id, path, position)
  end

  # Public: Global ID generator. Allows to generate IDs without a commit comment
  # thread object.
  #
  # Returns String
  def self.global_id_for(repository_id, commit_id, path, position)
    "#{repository_id}:#{commit_id}:#{path}:#{position}"
  end

  # Respond to this message like DeprecatedPullRequestReviewThread does. Not actually
  # needed for commit comment threads.
  #
  # TODO This should not be needed when the inline_comment_form partial is cleaned up.
  def clone_without_comments
    self.class.new(repository: repository, commit_id: commit_id)
  end

  def supports_multiple_threads_per_line?
    false
  end

  def ==(other)
    super || (other.instance_of?(self.class) && !id.nil? && id == other.id)
  end
  alias_method :eql?, :==

  def hash
    if id
      self.class.hash ^ id.hash
    else
      super
    end
  end

  protected def first_comment
    comments.first
  end
end
