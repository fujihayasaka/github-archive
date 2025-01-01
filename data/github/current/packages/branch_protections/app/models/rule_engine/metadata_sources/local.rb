# typed: strict
# frozen_string_literal: true

module RuleEngine
  module MetadataSources
    class Local < Base
      sig { params(blobs: T::Array[Types::BlobCandidate], commits: T::Array[Types::CommitCandidate]).void }
      def initialize(blobs: [], commits: [])
        @blobs = blobs
        @commits = commits
      end

      sig { override.returns(String) }
      def name
        "local"
      end

      sig { override.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(Collection[Types::BlobCandidate]) }
      def blobs(repository, phase, ref_update, cursor)
        Collection.new @blobs, nil
      end

      sig { override.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(Collection[Types::CommitCandidate]) }
      def commits(repository, phase, ref_update, cursor)
        Collection.new @commits, nil
      end
    end
  end
end
