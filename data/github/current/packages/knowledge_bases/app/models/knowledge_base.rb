# typed: true
# frozen_string_literal: true

# KnowledgeBase includes the subset of information from CosmosDB that we need to work
# with in the monolith.
class KnowledgeBase < T::Struct

  const :id, String
  const :name, String
  const :description, T.nilable(String)
  const :owner, User
  const :repositories, T::Array[Repository]
  const :content_sources, T::Array[KnowledgeBase::ContentSource]
end
