# typed: strict
# frozen_string_literal: true

module RuleEngine
  module MetadataSources
    # Abstract base class for accessing metadata for push rules
    class Base
      extend T::Helpers
      extend T::Sig

      abstract!

      sig { abstract.returns(String) }
      def name; end

      sig { abstract.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(MetadataSources::Collection[Types::BlobCandidate]) }
      def blobs(repository, phase, ref_update, cursor); end

      sig { abstract.params(repository: Repository, phase: T.nilable(RuleEngine::Types::Phase), ref_update: Git::Ref::Update, cursor: T.nilable(String)).returns(MetadataSources::Collection[Types::CommitCandidate]) }
      def commits(repository, phase, ref_update, cursor); end
    end
  end
end
