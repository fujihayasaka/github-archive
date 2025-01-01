# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module KnowledgeBases
  module Docset
    module Helpers
      extend T::Helpers

      Docset = T::type_alias do
        {
          id: String,
          name: String,
          description: T.nilable(String),
          createdByID: Integer,
          hardcoded: T.nilable(T::Boolean),
          ownerID: Integer,
          ownerLogin: String,
          ownerType: String,
          scopingQuery: T.nilable(String),
          sourceRepos: T.nilable(T::Array[SourceRepo]),
          repos: T::Array[String],
          iconHtml: T.nilable(String),
          visibility: String,
          visibleOutsideOrg: T.nilable(T::Boolean),
        }
      end

      SourceRepo = T.type_alias do
        {
            id: Integer,
            ownerID: Integer,
            paths: T::Array[String]
        }
      end

      # Public Methods

      sig { params(source_repo: Hash).returns(T.nilable(Hash)) }
      def self.get_source_repo_data(source_repo)
        repo = Repository.find_by(id: source_repo[:id])
        return nil unless repo

        owner = T.must(repo.owner)

        repo_data = {
          databaseId: repo.id,
          nameWithOwner: repo.name_with_display_owner,
          name: repo.name,
          isInOrganization: repo.in_organization?,
          owner: {
            databaseId: owner.id,
            avatarUrl: owner.unique_avatar_url,
            login: owner.display_login,
          },
          paths: source_repo[:paths]
        }
      end

      # Filters and decorates the given docsets for the current user.
      # - Filters the docsets to include only those visible to the current user.
      # - Secures and decorates each docset with additional information.
      # - Removes any docsets that are not viewable by the current user in case source repos and repos list have been emptied out
      sig { params(current_user: User, cap_filter: T.untyped, docsets: T::Array[Docset]).returns(T::Array[Hash]) }
      def self.filter_and_decorate_docsets(current_user:, cap_filter:, docsets:)
        kbs = filter_visible_docsets(current_user: current_user, cap_filter: cap_filter, docsets: docsets).map do |d|
          secure_and_decorate_docset(current_user: current_user, cap_filter: cap_filter, docset: d)
        end
        remove_unviewable_knowledge_bases(kbs)
      end

      # given a list of KBs, return only the ones that are core (ie MDN Webdocs),
      # belong to one of current user's SSO-authorized organizations, or are created by the current user
      sig { params(current_user: T.nilable(User), cap_filter: T.untyped, docsets: T::Array[Docset]).returns(T::Array[Docset]) }
      def self.filter_visible_docsets(current_user:, cap_filter:, docsets:)
        return [] unless current_user
        user_orgs = current_user.organizations
        user_org_ids = user_orgs.map(&:id)
        saml_unauthorized_org_ids = cap_filter.unauthorized_resource_ids(user_orgs)
        user_org_ids = user_org_ids - saml_unauthorized_org_ids

        docsets.filter do |docset|
          user_org_ids.include?(docset[:ownerID]) ||
            docset[:visibility] == "core" ||
            current_user.id == docset[:ownerID]
        end
      end

      sig { params(current_user_copilot_api: Copilot::User::CopilotApi, docset_name_or_id: String).returns(T.nilable(Docset)) }
      def self.find_docset(current_user_copilot_api:, docset_name_or_id:)
        resp = current_user_copilot_api.get_knowledge_base(knowledge_base_id: docset_name_or_id)
        resp[:kb]
      rescue CopilotAPI::NotFoundError
        nil
      end

      # given a docset, return a copy with any unviewable repos removed, and additional information added for the client
      sig { params(current_user: User, cap_filter: T.untyped, docset: Hash).returns(Hash) }
      def self.secure_and_decorate_docset(current_user:, cap_filter:, docset:)
        docset = docset.dup
        docset_owner = User.find_by(id: docset[:ownerID])

        if docset[:hardcoded]
          docset[:adminableByUser] = false
        else
          docset[:adminableByUser] = docset_owner&.adminable_by?(current_user) || false
        end
        docset[:avatarUrl] = docset_owner&.primary_avatar_url || ""
        docset[:ownerLogin] = docset_owner&.display_login || ""

        docset[:protectedOrganizations] = protected_org_logins_in_docset(cap_filter:, docset:)

        # Filter the raw repo list from CAPI to only include repos the user is logged in to view
        docset = remove_unviewable_docset_repos(current_user:, cap_filter:, docset:)

        docset = remove_unviewable_docset_source_repos(current_user:, cap_filter:, docset:)
      end

      # given a knowledge base, check permissions for each source repo in the knowledge base and remove those the
      # user is not authorized to view. Mutates the given knowledge base.
      # Since knowledge bases can contain repositories from many owners, it's
      # a distinct possibility that the user who creates the knowledge base could
      # have different permissions than the users who consume the knowledge base.
      # Different users will have different sets of repos they might have access to.
      sig { params(current_user: User, cap_filter: T.untyped, docset: Hash).returns(Hash) }
      def self.remove_unviewable_docset_source_repos(current_user:, cap_filter:, docset:)
        source_repos = docset[:sourceRepos]
        if source_repos.nil? || source_repos.empty?
          return docset
        end

        ids = source_repos.map { |repo| repo[:id] }
        repos_in_docset = Repository.where(id: ids)
        authorized_source_repos = repos_in_docset.reject { |repo| !repo.readable_by?(current_user) || !cap_filter.unauthorized([repo]).empty? }
        authorized_repo_ids = authorized_source_repos.map { |repo| repo.id }

        docset[:sourceRepos] = source_repos.select { |repo| authorized_repo_ids.include?(repo[:id]) }

        docset
      end

      # Private Methods

      # organizations that own at least one repo in the docset but that the current user is not single-signed-on to
      sig { params(cap_filter: T.untyped, docset: Hash).returns(T::Array[String]) }
      def self.protected_org_logins_in_docset(cap_filter:, docset:)
        repos_in_docset = Repository.with_names_with_owners(docset[:repos] || [])
        orgs_in_docset = repos_in_docset.map { |repo| repo.owner }.select { |repo| repo.owner&.organization? }.uniq
        unauthorized_orgs = cap_filter.unauthorized_resources(orgs_in_docset)
        unauthorized_orgs.pluck(:display_login)
      end

      # given a knowledge base, check permissions for each repo in the knowledge base and remove those the
      # user is not authorized to view. Mutates the given knowledge base.
      # Since knowledge bases can contain repositories from many owners, it's
      # a distinct possibility that the user who creates the knowledge base could
      # have different permissions than the users who consume the knowledge base.
      # Different users will have different sets of repos they might have access to.
      sig { params(current_user: User, cap_filter: T.untyped, docset: Hash).returns(Hash) }
      def self.remove_unviewable_docset_repos(current_user:, cap_filter:, docset:)
        repos_key = docset[:repos] ? :repos : "repos"
        repos_in_docset = Repository.with_names_with_owners(docset[repos_key] || [])
        authorized_repos = repos_in_docset.reject { |repo| !repo.readable_by?(current_user) || !cap_filter.unauthorized([repo]).empty? }
        docset[repos_key] = authorized_repos.map(&:name_with_display_owner)

        docset
      end

      # Filters out knowledge bases if any of the following criteria are met:
      # - The :repos array is empty
      # - The :sourceRepos string is empty
      # These fields will be empty when the user doesn't have permissions to view
      # any of the repos in the knowledge base. This can happen for a few reasons.
      # If the current user needs to SSO into the repo's owner we'll remove the repo.
      # The current user might also simply not have permission to view the repo. Since
      # knowledge bases can contain repos from owners (even private repos owned by an
      # invidivual user), this is a distinct possibility.
      #
      # If the source repos and repos list have been emptied out, we won't be able to
      # perform an effective search, and it's not helpful to show this to the user.
      # We could also interpret a KB with no visible repos as something the user isn't
      # really allowed to see.
      sig { params(knowledge_bases: T::Array[T.any(Docset, Hash)]).returns(T::Array[T.any(Docset, Hash)]) }
      def self.remove_unviewable_knowledge_bases(knowledge_bases)
        knowledge_bases.reject do |kb|
          kb[:repos].blank? || kb[:sourceRepos].blank?
        end
      end

      private_class_method :protected_org_logins_in_docset, :remove_unviewable_docset_repos, :remove_unviewable_knowledge_bases
    end
  end
end
