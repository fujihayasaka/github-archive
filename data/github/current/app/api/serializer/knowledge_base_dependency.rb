# typed: true
# frozen_string_literal: true

module Api::Serializer::KnowledgeBaseDependency
  include Api::Serializer::UserDependency
  include Api::Serializer::RepositoriesDependency

  sig { params(kb: KnowledgeBase, options: T.untyped).returns(Hash) }
  def knowledge_base_hash(kb, options = {})
    {
      id: kb.id,
      name: kb.name,
      description: kb.description,
      owner: simple_user_hash(kb.owner, options),
      repositories: kb.repositories.map do |repository|
                      simple_repository_hash(repository, options)
                    end,
      content_sources: kb.content_sources.map do |content_source|
        {
          repository_id: content_source.repository_id,
          file_path_filters: content_source.file_path_filters
        }
      end
    }
  end
end
