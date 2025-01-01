# typed: true
# frozen_string_literal: true

class Hook::Payload::ActionsPushPayload < Hook::Payload::PushPayload

  COMMIT_PAYLOAD_LIMIT = 20

  # Builds the payload representation for the given commit.
  #
  # commit - A Commit instance.
  #
  # Returns a Hash.
  #
  # Overridden from Hook::Payload::PushPayload to drop the diffs and reduce the
  # total payload size.
  def commit_hash(commit)
    return unless commit

    hash = {
      id: commit.oid,
      tree_id: commit.tree_oid,
      distinct: distinct?(commit),
      message: commit.message,
      timestamp: commit.committed_date.xmlschema,
      url: commit_url(commit),
      author: {
        name: commit.author_name,
        email: commit.author_email,
      },
      committer: {
        name: commit.committer_name,
        email: commit.committer_email,
      },
    }
    if user = commit.author
      hash[:author][:username] = user.display_login
    end
    if user = commit.committer
      hash[:committer][:username] = user.display_login
    end
    hash
  end

  # Overidden from Pushes::CommitsHelper, called by Hook::Payload::PushPayload
  def commits_pushed
    commits = super
    commits.last(COMMIT_PAYLOAD_LIMIT)
  end
end
