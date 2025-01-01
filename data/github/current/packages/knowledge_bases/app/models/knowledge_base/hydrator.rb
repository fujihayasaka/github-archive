# typed: true
# frozen_string_literal: true
class KnowledgeBase
  # Hydrator turns the response from CAPI into a list of KnowledgeBases.
  class Hydrator
    class Result < T::Struct
      const :unauthorized_sso_org_ids, T::Array[Integer], default: []
      const :knowledge_bases, T::Array[KnowledgeBase], default: []
    end

    attr_reader :current_user, :cap_filter, :cosmos_data

    # Takes an array of documents from CosmosDB and turns them into KnowledgeBase
    # instances. Filters out Knowledge bases and repos that the current user
    # should not be able to view. Returns a list of orgs the user should SSO in to see.
    def self.from_cosmos_data(current_user:, cap_filter:, cosmos_data:)
      new(current_user:, cap_filter:, cosmos_data:).hydrate
    end

    def initialize(current_user:, cap_filter:, cosmos_data:)
      @current_user = current_user
      @cap_filter = cap_filter
      @cosmos_data = cosmos_data
    end

    def hydrate
      return Result.new unless current_user
      user_orgs = current_user.organizations

      saml_unauthorized_org_ids = cap_filter.unauthorized_resource_ids(user_orgs)
      authorized_org_ids = user_orgs.map(&:id) - saml_unauthorized_org_ids

      visible_kbs = Array.wrap(cosmos_data).filter do |kb|
        authorized_org_ids.include?(kb[:ownerID]) || current_user.id == kb[:ownerID]
      end

      kb_repo_nwos = visible_kbs.map { |kb| kb[:repos] }.flatten.uniq
      all_kb_repos = Repository.with_names_with_owners(kb_repo_nwos)
      cap_unauthorized_repos = cap_filter.unauthorized(all_kb_repos).resources

      readable_repos = all_kb_repos.filter { |repo| repo.readable_by?(current_user) && !cap_unauthorized_repos.include?(repo) }

      visible_repos_by_nwo = readable_repos.group_by { |repo| repo.name_with_display_owner }

      kb_owners_by_id = User.where(id: visible_kbs.map { |kb| kb[:ownerID] }.uniq).index_by(&:id)

      kb_list = visible_kbs.map do |kb|
        owner = kb_owners_by_id[kb[:ownerID]]
        repos = kb[:repos].map { |nwo| visible_repos_by_nwo[nwo] }.flatten.compact
        KnowledgeBase.new(
          id: kb[:id],
          name: kb[:name],
          description: kb[:description],
          owner: owner,
          repositories: repos,
        )
      end

      GitHub.logger.info(
        "KnowledgeBases::Public.from_cosmos_response",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.knowledge_bases.visible_kb_count": kb_list.count,
        # Limit to 100 to avoid spamming logs though it's unlikely we'd hit this limit
        "gh.knowledge_bases.visible_kb_owner_ids": kb_list.map { |kb| kb.owner.id }.uniq.first(100).join(","),
        "gh.knowledge_bases.saml_unauthorized_org_ids": saml_unauthorized_org_ids.first(100).join(","),
        "gh.actor.id": current_user&.id,
        "gh.request_id": GitHub.context[:request_id],
      )

      Result.new(
        knowledge_bases: kb_list.reject { |kb| kb.repositories.empty? },
        unauthorized_sso_org_ids: saml_unauthorized_org_ids.uniq
      )
    end
  end
end
