# typed: true
# frozen_string_literal: true

class Api::Topics < Api::App
  include Scientist
  include ReceiveSchemaWithOpenApi

  TopicsIndexQuery = PlatformClient.parse <<-'GRAPHQL'
    query($repositoryId: ID!, $limit: Int!, $numericPage: Int) {
      repository: node(id: $repositoryId) {
        ... on Repository {
          repositoryTopics(first: $limit, numericPage: $numericPage) {
            totalCount

            ...Api::Serializer::TopicsDependency::RepositoryTopicsFragment
          }
        }
      }
    }
  GRAPHQL

  # List all Topics for a Repository
  # https://developer.github.com/v3/topics/#list-all-topics-for-a-repository
  get "/repositories/:repository_id/topics", operation_id: "repos/get-all-topics" do
    @accepted_scopes = ["repo"]
    control_access :get_repo, resource: repo = find_repo!, allow_integrations: true, allow_user_via_granular_actor: true

    variables = {
      repositoryId: repo.global_relay_id,
      limit: per_page,
      numericPage: pagination[:page],
    }

    results = platform_execute(TopicsIndexQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    repository_topics = results.data.repository.repository_topics
    paginator.collection_size = repository_topics.total_count
    deliver :graphql_repository_topics_array, repository_topics
  end

  UpdateTopicsQuery = PlatformClient.parse <<-'GRAPHQL'
    mutation($input: UpdateTopicsInput!, $limit: Int!) {
      updateTopics(input: $input) {
        repository {
          repositoryTopics(first: $limit) {
            totalCount

            ...Api::Serializer::TopicsDependency::RepositoryTopicsFragment
          }
        }
      }
    }
  GRAPHQL

  # Replace all Topics for a Repository
  # https://developer.github.com/v3/topics/#replace-all-topics-for-a-repository
  put "/repositories/:repository_id/topics", operation_id: "repos/replace-all-topics" do
    @accepted_scopes = ["repo"]

    repo = find_repo!

    control_access :manage_topics,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    topics = receive_with_schema("topic", "replace-legacy")

    variables = {
      input: {
        repositoryId: repo.global_relay_id,
        topicNames: topics["names"],
      },
      limit: topics["names"].size,
    }

    results = platform_execute(UpdateTopicsQuery, variables: variables)

    if results.errors.all.any?
      deliver_error! 422, errors: results.errors.all.values.flatten
    end

    repository_topics = results.data.update_topics.repository.repository_topics

    deliver :graphql_repository_topics_array, repository_topics
  end
end
