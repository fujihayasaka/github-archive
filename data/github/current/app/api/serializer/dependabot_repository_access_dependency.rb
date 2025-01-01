# typed: true
# frozen_string_literal: true

module Api::Serializer::DependabotRepositoryAccessDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer::RepositoriesDependency }

  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def repository_access_hash(data, options = {})
    repository_hashes = Array(data[:repositories]).map do |repository|
      simple_repository_hash(repository, options)
    end

    response = { accessible_repositories: repository_hashes }
    response[:default_level] = data[:default_level] if data[:default_level]

    response
  end
end
