# typed: true
# frozen_string_literal: true

class Contribution::CreatedRepository < Contribution
  LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST = [
    :active,
    :created_at,
    :disabled_at,
    :id,
    :name,
    :organization_id,
    :owner_id,
    :owner_login,
    :parent_id,
    :primary_language_name_id,
    :public,
    :source_id,
    :template,
    :user_hidden,
  ].freeze

  # Limit on the number of created repositories contributed to.
  # Actual number selected will be REPO_LIMIT + 1 to allow callers to tell when
  # a user created more repositiories than the limit allows.
  # https://github.com/github/github/issues/71686
  REPO_LIMIT = 100

  def repository
    subject
  end

  def associated_subject
    repository
  end

  def organization_id
    repository.try(:organization_id)
  end

  def eql?(other_contribution)
    other_contribution.respond_to?(:repository) && repository == other_contribution.repository
  end

  def hash
    repository.hash
  end

  def description
    repository.description
  end

  def primary_language
    repository.primary_language_name
  end

  def repository_id
    repository.id
  end

  def contributors(viewer:)
    return @contributors[viewer] if defined?(@contributors) && @contributors[viewer]

    @contributors ||= {}
    users = repository.top_contributors(
      limit: 5,
      skip_private_profiles: true,
      viewer: viewer
    )
    @contributors[viewer] = if users == [user]
      []
    else
      users
    end
  end

  def repo_type_icon
    repository.repo_type_icon
  end

  def occurred_at
    repository.created_at
  end

  def name
    repository.name
  end

  def id
    repository_id
  end

  def platform_type_name
    "CreatedRepositoryContribution"
  end

  # Public: Returns repositories created within the time range, ordered by most
  # recent first. Includes forks.
  def self.subjects_for(
    user,
    date_range:,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    Contribution.measure("created_repository_subjects_for", tags: ["lightweight:#{lightweight}", "using_contribution_fetchers:false"]) do
      # Since CreatedRepository is only for user-owned repositories, return none
      # if scoping by an organization.
      # And don't use excluded_organization_ids.
      return Repository.none if organization_id

      scope = user.repositories.where(created_at: date_range_to_time_range(date_range))

      if lightweight
        scope = scope.reselect(LIGHTWEIGHT_ATTRIBUTE_SELECT_LIST)
      end

      scope.
        limit(REPO_LIMIT + 1). # add one to REPO_LIMIT to allow callers to tell when user is over the limit
        reorder("created_at DESC"). # need this here to avoid unintended alphabetical sort by repo name
        to_a
    end
  end

  # Public: Returns a single root Repository, the first the user created.
  def self.first_subject_for(user, excluded_organization_ids: [])
    Contribution.measure("created_repository_first_subject_for") do
      # Since CreatedRepository is only for user-owned repositories, don't use
      # excluded_organization_ids.
      index = "index_repositories_on_owner_id_and_name_and_active"
      # See https://github.com/github/github/issues/62302
      user.repositories.from("`#{Repository.table_name}` FORCE INDEX (#{index})").
      network_roots.first
    end
  end
end
