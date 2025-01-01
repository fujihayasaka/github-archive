# typed: strict
# frozen_string_literal: true

module ReposPicker::RepositoriesPayloadDependency
  FilterRepository = T.type_alias do
    {
      id: Integer,
      nodeId: String,
      name: String,
      ownerLogin: String,
      visibility: String,
    }
  end

  sig { params(repositories: T::Array[Repository]).returns(T::Array[FilterRepository]) }
  def repositories_payload(repositories)
    repositories.map { |repository| repository_payload(repository) }
  end

  sig { params(repository: Repository).returns(FilterRepository) }
  def repository_payload(repository)
    {
      id: repository.id,
      nodeId: repository.global_relay_id,
      name: repository.name,
      ownerLogin: repository.owner&.display_login,
      visibility: repository.visibility,
    }
  end
end
