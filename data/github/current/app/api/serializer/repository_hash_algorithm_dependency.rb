# typed: true
# frozen_string_literal: true

module Api::Serializer::RepositoryHashAlgorithmDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  def repository_hash_algorithm_hash(repo, options = {})
    {
      hash_algorithm: repo.hash_algo.name.to_s
    }
  end
end
