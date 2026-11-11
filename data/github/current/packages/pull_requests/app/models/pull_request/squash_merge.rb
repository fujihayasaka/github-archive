# typed: true
# frozen_string_literal: true

class PullRequest::SquashMerge
  # Public: Instantiate an object to represent a squashed merge commit.
  #
  # repository   - The Repository in which the merge_commit lives.
  # commit_oid   - The object ID of the merge commit to squash.
  # require_signature - If true, raise an exception if the commit signing
  #                     fails. If false, proceed silently whether the commit
  #                     signing succeeds or not.
  def initialize(repository:, commit_oid:, require_signature:)
    @repository = repository
    @commit_oid = commit_oid
    @require_signature = require_signature || false
  end

  # Public: Rewrite the merge commit to remove all but one parent with a new
  # author, committer, and commit message
  #
  # author_email - Email address to associate with the squashed commit.
  # author_name  - Name to associate with the squashed commit.
  # time_zone    - Time zone in which the author's time will be localized.
  # title        - First line of the squash commit message. This will be used
  #                as the subject line of the commit.
  # message      - The rest of the squash commit message.
  #
  # Returns the object id of the newly squashed commit. Raises
  # Repositories::Error::SignatureError if we're unable to sign the
  # commit and the require_signature option is true.
  def perform(author_email:, author_name:, time_zone:, title:, message:, commit_time: nil)
    commit_time ||= Time.current
    commit_data = {
      "author" => {
        "email" => author_email,
        "name"  => author_name,
        "time"  => commit_time.in_time_zone(time_zone).iso8601,
      },
      "committer" => {
        "email" => GitHub.web_committer_email,
        "name"  => GitHub.web_committer_name,
        "time"  => commit_time.iso8601,
      },
      "message" => "#{title}\n\n#{message}",
    }

    rewrite_merge_commit(commit_data)
  end

  private

  def rewrite_merge_commit(commit_data)
    Repositories.domain.commits.rewrite_merge_commit(
      repository: @repository,
      commit_oid: @commit_oid,
      info: commit_data,
      squash: true,
      require_signature: @require_signature
    )
  end
end
