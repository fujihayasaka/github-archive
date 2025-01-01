# typed: strict
# frozen_string_literal: true

module RulesEngine
  module CandidateTestHelper
    extend T::Sig
    include RefUpdateTestHelper

    sig { params(ref_update: Git::Ref::Update).returns(Git::Ref::Update) }
    def create_ref_candidate(ref_update)
      ref_update
    end

    sig { params(oid: String, commit_oid: String, path: String, size: Integer, contents: String).returns(RuleEngine::MetadataSources::Types::BlobCandidate) }
    def create_blob_candidate(oid: "0000", commit_oid: "0000", path: "README.md", size: 88, contents: "Hello world")
      RuleEngine::MetadataSources::Types::BlobCandidate.new(oid:, commit_oid:, path:, size:, contents:)
    end

    sig do
      params(
        id: String,
        message: String,
        author_email: String,
        committer_email: String,
        gpg_signature: String,
      ).returns(RuleEngine::MetadataSources::Types::CommitCandidate)
    end
    def create_commit_candidate(id: create_random_sha, message: "Initial commit", author_email: "monalisa@github.com", committer_email: "monalisa@github.com", gpg_signature: "")
      oid = GitHub::Spokes::Proto::Types::V1::ObjectID.new(id: id)
      commit_content = GitHub::Spokes::Proto::Types::V1::Commit.new(
        message: message,
        gpg_signature: gpg_signature,
        author: GitHub::Spokes::Proto::Types::V1::Attribution.new(email: author_email),
        committer: GitHub::Spokes::Proto::Types::V1::Attribution.new(email: committer_email),
      )

      commit = GitHub::Spokes::Proto::Commits::V1::CommitItem.new(oid:, commit_content:)

      RuleEngine::MetadataSources::Types::CommitCandidate.from_spokes(commit)
    end
  end
end
