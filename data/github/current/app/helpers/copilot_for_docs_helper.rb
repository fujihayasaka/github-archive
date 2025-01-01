# typed: true
# frozen_string_literal: true

module CopilotForDocsHelper
  extend T::Sig
  extend T::Helpers

  include Kernel
  include GitHub::Memoizer
  include FeatureFlagHelper

  requires_ancestor { ApplicationController }

  def report_error(e, action_name)
    Failbot.report(e)
    GitHub.dogstats.increment("copilot.chat.error", tags: [
      "error:#{e.class.name}",
      "action:#{action_name}",
    ])
  end

  sig { returns Copilot::User::CopilotApi }
  def current_user_copilot_api
    token = GitHub.decode_and_decrypt_capi_token(request&.headers[CopilotAPI::TOKEN_HEADER])

    T.must(current_user).copilot_api(
      integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID,
      session: user_session,
      real_ip: request&.remote_ip,
      token: token,
    )
  end

  # organizations that the user admins, and is also SSO'd to, and is on a Copilot Enterprise plan
  sig { params(user: User).returns(T::Array[Hash]) }
  def administrated_copilot_enterprise_organizations(user)
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

  # organizations that own at least one repo in the docset but that the current user is not single-signed-on to
  sig { params(docset: Hash).returns(T::Array[String]) }
  def protected_org_logins_in_docset(docset)
    repos_in_docset = Repository.with_names_with_owners(docset[:repos] || [])
    orgs_in_docset = repos_in_docset.map { |repo| repo.owner }.select { |repo| repo.owner&.organization? }.uniq
    unauthorized_orgs = cap_filter.unauthorized_resources(orgs_in_docset)
    unauthorized_orgs.pluck(:display_login)
  end

  sig { params(nwo: String).returns(T.nilable(Hash)) }
  def get_repo_data(nwo)
    repo = Repository.with_name_with_owner(nwo)
    return nil unless repo

    owner = T.must(repo.owner)

    repo_data = {
      databaseId: repo.id,
      nameWithOwner: nwo,
      name: repo.name,
      isInOrganization: repo.in_organization?,
      owner: {
        databaseId: owner.id,
        avatarUrl: owner.unique_avatar_url,
        login: owner.display_login,
      }
    }
  end

  sig { params(source_repo: Hash).returns(T.nilable(Hash)) }
  def get_source_repo_data(source_repo)
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

  # given a list of KBs, return only the ones that are core (ie MDN Webdocs),
  # belong to one of current user's SSO-authorized organizations, or are created by the current user
  sig { params(docsets: T::Array[Docset]).returns(T::Array[Docset]) }
  def filter_visible_docsets(docsets)
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

  sig { params(docset_name_or_id: String).returns(T.nilable(Docset)) }
  def find_docset(docset_name_or_id)
    resp = current_user_copilot_api.get_knowledge_base(knowledge_base_id: docset_name_or_id)
    resp[:kb]
  rescue CopilotAPI::NotFoundError
    nil
  end

  # given a knowledge base, check permissions for each repo in the knowledge base and remove those the
  # user is not authorized to view. Mutates the given knowledge base.
  # Since knowledge bases can contain repositories from many owners, it's
  # a distinct possibility that the user who creates the knowledge base could
  # have different permissions than the users who consume the knowledge base.
  # Different users will have different sets of repos they might have access to.
  sig { params(docset: Hash).returns(Hash) }
  def remove_unviewable_docset_repos(docset)
    repos_key = docset[:repos] ? :repos : "repos"
    repos_in_docset = Repository.with_names_with_owners(docset[repos_key] || [])
    authorized_repos = repos_in_docset.reject { |repo| !repo.readable_by?(current_user) || !cap_filter.unauthorized([repo]).empty? }
    docset[repos_key] = authorized_repos.map(&:name_with_display_owner)

    docset
  end

  # given a knowledge base, check permissions for each source repo in the knowledge base and remove those the
  # user is not authorized to view. Mutates the given knowledge base.
  # Since knowledge bases can contain repositories from many owners, it's
  # a distinct possibility that the user who creates the knowledge base could
  # have different permissions than the users who consume the knowledge base.
  # Different users will have different sets of repos they might have access to.
  sig { params(docset: Hash).returns(Hash) }
  def remove_unviewable_docset_source_repos(docset)
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

  # given a knowledge base, check permissions for each repo in the scoping query
  # and remove those user is not authorized to view. Mutates the given knowledge base.
  #
  # Since knowledge bases can contain repositories from many owners, it's
  # a distinct possiblity that the user who creates the knowledge base could
  # have different permissions than the users who consume the knowledge base.
  # Different users will have different sets of repos they might have access to.
  #
  # The scoping query and the list of repos in the knowledge base will be filtered
  # in tandem. We should never see a case where a repo is present in the scoping query
  # but not in the array of repos.
  sig { params(docset: Hash).returns(Hash) }
  def remove_unviewable_docset_scoping_query_repos(docset)
    CopilotForDocs::DocsetScopingQuerySanitizer.remove_unviewable_scoping_query_repos(docset, cap_filter, current_user)
  end

  # Filters out knowledge bases if any of the following criteria are met:
  # - The :repos array is empty
  # - The :scopingQuery string is empty
  # These fields will be empty when the user doesn't have permissions to view
  # any of the repos in the knowledge base. This can happen for a few reasons.
  # If the current user needs to SSO into the repo's owner we'll remove the repo.
  # The current user might also simply not have permission to view the repo. Since
  # knowledge bases can contain repos from owners (even private repos owned by an
  # invidivual user), this is a distinct possibility.
  #
  # If the scoping query and repos list have been emptied out, we won't be able to
  # perform an effective search, and it's not helpful to show this to the user.
  # We could also interpret a KB with no visible repos as something the user isn't
  # really allowed to see.
  sig { params(knowledge_bases: T::Array[T.any(Docset, Hash)]).returns(T::Array[T.any(Docset, Hash)]) }
  def remove_unviewable_knowledge_bases(knowledge_bases)
    knowledge_bases.reject do |kb|
      kb[:repos].blank? || kb[:scopingQuery].blank?
    end
  end

  # given a docset, return a copy with any unviewable repos removed, and additional information added for the client
  sig { params(docset: Hash).returns(Hash) }
  def secure_and_decorate_docset(docset)
    docset = docset.dup
    docset_owner = User.find_by(id: docset[:ownerID])

    if docset[:hardcoded]
      docset[:adminableByUser] = false
    else
      docset[:adminableByUser] = docset_owner&.adminable_by?(current_user) || false
    end
    docset[:avatarUrl] = docset_owner&.primary_avatar_url || ""
    docset[:ownerLogin] = docset_owner&.display_login || ""

    docset[:protectedOrganizations] = protected_org_logins_in_docset(docset)

    # Filter the raw repo list and scopingQuery from CAPI to only include repos the user is logged in to view
    docset = remove_unviewable_docset_repos(docset)

    docset = remove_unviewable_docset_source_repos(docset)

    docset = remove_unviewable_docset_scoping_query_repos(docset)
  end

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
      scopingQuery: String,
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
end
