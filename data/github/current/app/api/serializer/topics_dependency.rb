# typed: true
# frozen_string_literal: true

module Api::Serializer::TopicsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  ALLOWED_TOPIC_RELATION_FIELDS = [
    :id,
    :name,
    :topic_id,
    :relation_type,
  ]

  RepositoryTopicsFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on RepositoryTopicConnection {
      edges {
        node {
          topic {
            name
          }
        }
      }
    }
  GRAPHQL

  def graphql_repository_topics_array(repository_topics, options = {})
    repository_topics = RepositoryTopicsFragment.new(repository_topics)
    {
      names: repository_topics.edges.map { |edge| edge.node.topic.name },
    }
  end

  def search_topic_hash(topic_result, options = {})
    topic = topic_result["_model"]
    return unless topic

    hash = {
      name: topic.name,
      display_name: topic.display_name,
      short_description: topic.short_description,
      description: topic.description,
      created_by: topic.created_by,
      released: topic.released,
      created_at: time(topic.created_at),
      updated_at: time(topic.updated_at),
      featured: topic.featured?,
      curated: topic.curated?,
    }

    if options.accepts_semantic_version?("extended-search-results")
      hash.update \
        repository_count: topic.repositories.count,
        aliases: topic.topic_relations.alias.map { |item| item.as_json(only: ALLOWED_TOPIC_RELATION_FIELDS) },
        related: topic.topic_relations.related.map { |related| related.as_json(only: ALLOWED_TOPIC_RELATION_FIELDS) },
        logo_url: topic.logo_url
    end
    hash
  end
end
