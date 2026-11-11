# typed: strict
# frozen_string_literal: true

module RuleEngine
  module MetadataSources
    module Types
      Candidate = T.type_alias { T.any(BlobCandidate, CommitCandidate, Git::Ref::Update) }
    end
  end
end
