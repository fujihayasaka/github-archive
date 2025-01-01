# typed: true
# frozen_string_literal: true

module Api::Serializer::KnowledgeBaseDependency
  include Api::Serializer::UserDependency
  include Api::Serializer::RepositoriesDependency
  extend T::Sig

  sig { params(kb: KnowledgeBase, options: T.untyped).returns(Hash) }
  def knowledge_base_hash(kb, options = {})
    {
      id: kb.id,
      name: kb.name,
      description: kb.description,
      owner: simple_user_hash(kb.owner, options),
      repositories: kb.repositories.map do |repository|
                      simple_repository_hash(repository, options)
                    end
    }
  end
end
