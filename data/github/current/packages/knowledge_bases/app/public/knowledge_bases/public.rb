# typed: strict
# frozen_string_literal: true

module KnowledgeBases
  module Public
    extend T::Helpers

    # From https://github.com/github/copilot-api/blob/21f84a8c640cee3cf9dc77859dde67587a00a712/pkg/kb/store/kb.go#L79
    # This is the shape of the data we get from Cosmos by way of CAPI
    CosmosResult = T::type_alias do
      {
        id: String,
        name: String,
        description: T.nilable(String),
        createdByID: Integer,
        ownerID: Integer,
        ownerLogin: String,
        ownerType: String,
        scopingQuery: T.nilable(String),
        sourceRepos: T.nilable(T::Array[KnowledgeBase::ScopingQuery::SourceRepo]),
        repos: T::Array[String],
        iconHtml: T.nilable(String),
        visibility: String,
        visibleOutsideOrg: T::Boolean,
      }
    end

    # Turns the documents from Cosmos into a list of Knowledge bases visible to the current user,
    # with repositories filtered as well. The result includes a list of organization IDs that require SSO.
    sig { params(current_user: T.nilable(User), cap_filter: T.untyped, cosmos_data: T.any(CosmosResult, T::Array[CosmosResult]), authorized_org_id: T.nilable(Integer), accessible_repos: T.nilable(T::Array[Repository])).returns(KnowledgeBase::Hydrator::Result) }
    def self.from_cosmos_response(current_user:, cap_filter:, cosmos_data:, authorized_org_id: nil, accessible_repos: [])
      KnowledgeBase::Hydrator.from_cosmos_data(current_user:, cap_filter:, cosmos_data:, authorized_org_id:, accessible_repos:)
    end
  end
end
