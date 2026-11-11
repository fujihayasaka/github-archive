# typed: strict
# frozen_string_literal: true

class RuleEngine::MetadataSources::Types::CommitCandidate

  sig { returns(T.nilable(String)) }
  attr_reader :oid

  sig { returns(T.nilable(String)) }
  attr_reader :author_email

  sig { returns(T.nilable(String)) }
  attr_reader :committer_email

  sig { returns(T.nilable(String)) }
  attr_reader :message

  sig { returns(T.nilable(String)) }
  attr_reader :gpg_signature

  sig do
    params(
      oid: T.nilable(String),
      message: T.nilable(String),
      author_email: T.nilable(String),
      committer_email: T.nilable(String),
      gpg_signature: T.nilable(String),
    )
    .void
  end
  def initialize(oid:, message:, author_email:, committer_email:, gpg_signature:)
    @oid = oid
    @message = message
    @author_email = author_email
    @committer_email = committer_email
    @gpg_signature = gpg_signature
    @gpg_signature = gpg_signature
  end

  sig { params(commit: GitHub::Spokes::Proto::Commits::V1::CommitItem).returns(RuleEngine::MetadataSources::Types::CommitCandidate) }
  def self.from_spokes(commit)
    self.new(
      oid: commit.oid&.id,
      message: commit.commit_content&.message,
      author_email: commit.commit_content&.author&.email,
      committer_email: commit.commit_content&.committer&.email,
      gpg_signature: commit.commit_content&.gpg_signature,
    )
  end
end
