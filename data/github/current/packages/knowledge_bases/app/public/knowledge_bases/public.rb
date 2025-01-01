# typed: true # rubocop:todo Sorbet/StrictSigil
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

    # Logs the indexing status of the embeddings for a knowledge base for chat settings context
    sig { params(method: String, kb_id: T.untyped, repo_id: Integer, repo_nwo: String, status: T.untyped).void }
    def self.log_indexing_status(method, kb_id, repo_id, repo_nwo, status)
      GitHub.dogstats.increment("chat_settings.knowledge_bases.#{method}.embeddings_indexing", tags: ["status:#{status}"])
      GitHub.logger.info("chat_settings.knowledge_bases.#{method}.embeddings_indexing", {
        "gh.copilot.knowledge_base.id": kb_id,
        "gh.copilot.knowledge_base.repo_id": repo_id,
        "gh.copilot.knowledge_base.repo_nwo": repo_nwo,
        "gh.copilot.knowledge_base.embeddings_indexing_status": status,
      })
    end

    # organizations that the user admins, and is also SSO'd to, and is on a Copilot Enterprise plan
    sig { params(user: User).returns(T::Array[Hash]) }
    def self.administrated_copilot_enterprise_organizations(user)
      orgs = user.organizations

      Configurable.preload_configuration(orgs)

      allowed_orgs = orgs.filter do |org|
        org.adminable_by?(user) &&
        !org.has_sdn_new_org_with_free_plan_restriction? &&
        Copilot::Organization.new(org).can_use_copilot_enterprise_features?
      end

      orgs.select { |org| allowed_orgs.include?(org) }.map do |org|
        {
          id: org.id,
          name: org.name,
          login: org.display_login,
          avatarUrl: org.primary_avatar_url,
        }
      end
    end

    sig { params(source_repo: Hash).returns(T.nilable(Hash)) }
    def self.get_source_repo_data(source_repo)
      KnowledgeBases::Docset::Helpers.get_source_repo_data(source_repo)
    end

    # Filters and decorates the given docsets for the current user.
    # - Filters the docsets to include only those visible to the current user.
    # - Secures and decorates each docset with additional information.
    # - Removes any docsets that are not viewable by the current user in case source repos and repos list have been emptied out
    sig { params(current_user: User, cap_filter: T.untyped, docsets: T::Array[KnowledgeBases::Docset::Helpers::Docset]).returns(T::Array[Hash]) }
    def self.filter_and_decorate_docsets(current_user:, cap_filter:, docsets:)
      KnowledgeBases::Docset::Helpers.filter_and_decorate_docsets(current_user:, cap_filter:, docsets:)
    end

    # given a list of KBs, return only the ones that are core (ie MDN Webdocs),
    # belong to one of current user's SSO-authorized organizations, or are created by the current user
    sig { params(current_user: T.nilable(User), cap_filter: T.untyped, docsets: T::Array[KnowledgeBases::Docset::Helpers::Docset]).returns(T::Array[KnowledgeBases::Docset::Helpers::Docset]) }
    def self.filter_visible_docsets(current_user:, cap_filter:, docsets:)
      KnowledgeBases::Docset::Helpers.filter_visible_docsets(current_user:, cap_filter:, docsets:)
    end

    sig { params(current_user_copilot_api: Copilot::User::CopilotApi, docset_name_or_id: String).returns(T.nilable(KnowledgeBases::Docset::Helpers::Docset)) }
    def self.find_docset(current_user_copilot_api:, docset_name_or_id:)
      KnowledgeBases::Docset::Helpers.find_docset(current_user_copilot_api:, docset_name_or_id:)
    end

    # given a docset, return a copy with any unviewable repos removed, and additional information added for the client
    sig { params(current_user: User, cap_filter: T.untyped, docset: Hash).returns(Hash) }
    def self.secure_and_decorate_docset(current_user:, cap_filter:, docset:)
      KnowledgeBases::Docset::Helpers.secure_and_decorate_docset(current_user:, cap_filter:, docset:)
    end
  end
end
