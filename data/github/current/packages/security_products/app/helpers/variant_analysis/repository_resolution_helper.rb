# typed: true
# frozen_string_literal: true

# Resolves repository objects out of repository nwos, lists and owners.
module VariantAnalysis::RepositoryResolutionHelper
  # Public: Resolves repository objects out of either:
  # - repository_nwos - a list of repository "name with owner" (e.g. owner/repo_name)
  # - repository_lists - an array of pre-built repository lists
  # - repository_owners - an array of repo owners
  # Plus additional fields:
  # - language - to indicate the language of the repositories.
  # - current_user - the user triggering the variant analysis.
  # - cap_filter - defines the repositories the user has access to.
  #
  # Examples:
  #
  #   resolve_repositories(
  #     current_user: current_user,
  #     cap_filter: cap_filter,
  #     language: "java",
  #     repository_nwos: ["github/codeql", "github/codeql-go"]
  #   )
  #   => { repo_ids: [1,2], invalid_repo_nwos: [], invalid_repo_lists: [], invalid_owners: [] }
  #
  # We want to be careful to not leak information about private repositories, so we're returning a list
  # of invalid_repo_nwos. This is built from the original user input rather than the nwos we find
  # in the database.
  sig do
    params(
      current_user: ::User,
      cap_filter: T.any(::ConditionalAccess::Web::Filter, ::ConditionalAccess::Api::Public::Filter),
      language: String,
      repository_nwos: T.nilable(T::Array[String]),
      repository_lists: T.nilable(T::Array[String]),
      repository_owners: T.nilable(T::Array[String])
    ).returns(
      T::Hash[Symbol, T::Array[String]]
    )
  end
  def resolve_repositories(
    current_user:,
    cap_filter:,
    language:,
    repository_nwos: nil,
    repository_lists: nil,
    repository_owners: nil
  )
    result = {
      repo_ids: [],
      invalid_repo_nwos: [],
      invalid_repo_lists: [],
      invalid_owners: []
    }

    if repository_nwos
      accessible_repos = resolve_accessible_repos(repository_nwos, current_user, cap_filter).pluck(:id, :name, :owner_login)
      result[:repo_ids] += accessible_repos.map(&:first)

      if accessible_repos.count < repository_nwos.count
        accessible_nwos = accessible_repos.map { |_id, name, owner_login| "#{User.to_display_login(owner_login)}/#{name}".downcase }
        result[:invalid_repo_nwos] += repository_nwos.reject { |nwo| accessible_nwos.include?(nwo.downcase) }
      end
    end

    if repository_lists
      nwos = T.let([], T::Array[String])
      repository_lists.each do |repository_list|
        list_nwos = resolve_repository_list_nwos(repository_list, language)
        if list_nwos.blank?
          result[:invalid_repo_lists] << repository_list
        else
          nwos += list_nwos
        end
      end

      result[:repo_ids] += resolve_accessible_repos(nwos, current_user, cap_filter).pluck(:id)
    end

    if repository_owners
      all_owner_repo_ids = T.let([], T::Array[Integer])

      repository_owners.each do |repository_owner|
        resolved_owner_repo_ids = resolve_repository_owner_repos(repository_owner, language)
        if resolved_owner_repo_ids.nil?
          result[:invalid_owners] << repository_owner
        else
          all_owner_repo_ids += resolved_owner_repo_ids
        end
      end

      result[:repo_ids] += find_accessible_repositories(all_owner_repo_ids, current_user, cap_filter).pluck(:id)
    end

    result
  end

  def resolve_repo_nwos_from_ids(repo_ids)
    return {} if repo_ids.blank?

    repo_ids.each_slice(5000).map do |ids|
      Repository.find(T.let(ids, T::Array[Integer]))
        .pluck(:id, :name, :owner_login)
        .to_h { |id, name, owner_login| [id, "#{User.to_display_login(owner_login)}/#{name}"] }
    end.inject(:merge)
  end

  def find_accessible_repositories_with_ids(repository_ids, current_user, cap_filter)
    return {} if repository_ids.empty?

    repos = find_accessible_repositories(repository_ids, current_user, cap_filter)

    repos.pluck(:id, :owner_login, :name, :public, Repository.stargazer_count_column, :updated_at).to_h do |id, owner_login, name, public, stargazer_count, updated_at|
      owner_display_login = User.to_display_login(owner_login)
      [
        id,
        {
          id: id,
          owner: owner_display_login,
          name: name,
          nwo: "#{owner_display_login}/#{name}",
          private: !public,
          stargazer_count: stargazer_count,
          updated_at: updated_at
        }
      ]
    end
  end

  def repository_id_accessible?(repository_id, current_user, cap_filter, exclude_token_policies: false)
    find_accessible_repositories([repository_id], current_user, cap_filter, exclude_token_policies:).pluck(:id).include?(repository_id)
  end

  private

  def find_accessible_repositories(repository_ids, current_user, cap_filter, exclude_token_policies: false)
    associated_repository_ids = find_associated_repository_ids(repository_ids, current_user, cap_filter)
    accessible_repositories = Repositories::Public.accessible_repositories(
      repository_ids: repository_ids, associated_repository_ids: associated_repository_ids
    )

    exclude = if exclude_token_policies
      # When authenticated using a signed auth token/remote auth token and updating repository tasks,
      # we need to skip some coditional access policies:
      # - saml: SATs cannot be authorized for SAML.
      # - ip_allowlist: the request is being made from a GitHub action workflow.
      #
      # It is safe to ignore these policies here because to obtain a valid SAT the user must have gone
      # through the process to create a variant analsis, and during that process the user's original access
      # token was used to check repository access, including SAML and IP allowlist checks.
      #
      # If the SAT is leaked from the Actions workflow, this would only allow an attacker to update repo tasks
      # for this variant analysis. It does not allow the user to see any other information about the repositories
      # analysed.
      #
      # There are two minor race condition in which the user would be able to update a repo task without being
      # fully authorized:
      # - The SAML authorization can be revoked on an access token
      # - SAML authorization or IP allowlist enforcement can be set up after the variant analysis is created
      # In both cases, the user would be able to update the repo task without having the correct authorization
      # for the repository. This would only be for a short period of time since a SAT is only valid for 24 hours.
      [:saml, :ip_allowlist]
    else
      []
    end

    cap_filter.authorized_resources(accessible_repositories, exclude: exclude)
  end

  def find_associated_repository_ids(repository_ids, current_user, cap_filter)
    return [] unless !!current_user

    associated_repository_ids = Set.new(current_user.associated_repository_ids(min_action: :read, repository_ids: repository_ids))
    ProgrammaticActor::RepositoryFilter.perform(
      actor: current_user,
      repository_ids: associated_repository_ids,
      resource: "contents",
    ).to_a
  end

  def resolve_accessible_repos(nwos, current_user, cap_filter)
    repo_ids = T.let([], T::Array[Integer])

    nwos.each_slice(500) do |nwos_slice|
      repo_ids += Repository.with_names_with_owners(nwos_slice).pluck(:id)
    end

    find_accessible_repositories(repo_ids, current_user, cap_filter)
  end

  def resolve_repository_list_nwos(list_name, language)
    VariantAnalysis::CodeScanningRepoLists.get_repo_list(language, list_name)
  end

  def resolve_repository_owner_repos(owner_name, language)
    owner = User.find_by_login(owner_name)

    return nil if owner.nil?

    # We need to get the IDs of all repositories in the user/org.
    # Then we can find those with the correct language or an uploaded CodeQL DB.
    all_repo_ids = owner.repositories.pluck(:id).to_set
    repo_ids = Set.new

    language_name_ids = language_name_ids_for_codeql_language(language)
    unless language_name_ids.empty?
      all_repo_ids.each_slice(1000) do |repo_ids_slice|
        repo_ids += Repository.joins(:languages)
          .where(id: repo_ids_slice)
          .where(languages: { language_name_id: language_name_ids })
          .pluck(:id)
      end

      all_repo_ids -= repo_ids
    end

    all_repo_ids.each_slice(1000).flat_map do |repo_ids_slice|
      repo_ids += CodeqlDatabase.repos_and_languages_with_database(repo_ids_slice.map { |id| [id, language] }).map(&:first)
    end

    repo_ids.to_a
  end

  def language_name_ids_for_codeql_language(codeql_language)
    @language_name_ids ||= Hash.new do |h, key|
      language_names = CodeqlVariantAnalysis::CODEQL_TO_LINGUIST_LANGUAGES[key]
      h[key] = language_names.nil? ? [] : LanguageName.where(name: language_names).pluck(:id)
    end
    @language_name_ids[codeql_language]
  end
end
