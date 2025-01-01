# typed: true
# frozen_string_literal: true

class CommitContribution::RepositoryValidator
  include GitHub::Memoizer

  BATCH_SIZE = 100

  # A RepositoryValidator is used to determine if a commit contribution should
  # be counted for a given user, based on whether that user has any connection
  # to a repository.
  #
  # user           - The User object
  # repository_ids - Array of IDs of suspect Repositories that need to be validated.
  #
  def initialize(user, repository_ids:)
    @user = user
    @repository_ids = repository_ids
  end

  # Public: Checks if the given repository is valid.
  #
  # As any user can push commits using another user's email, we try to
  # exclude commits that users might not have pushed on their own.
  #
  # We require at least one of the following to be true:
  # The user ...
  # - is a collaborator on the repository or is a member of the
  #   organization that owns the repository.
  # - has forked the repository.
  # - has opened a pull request or issue in the repository.
  # - has starred the repository.
  #
  # Most of these checks are arguable because they might result in false negatives.
  #
  # Returns a Boolean
  def valid_repository?(repository_id)
    return false unless repo_exists?(repository_id)
    return false if GitHub.user_abuse_mitigation_enabled? && block_between_users?(repository_id)
    return true if repo_accessible_to_user?(repository_id)
    return true if repo_had_issue_created_by_user?(repository_id)
    return true if in_repo_org?(repository_id)
    return true if repo_forked_by_user?(repository_id)
    unless disable_starred_repo_validation?
      return true if repo_starred_by_user?(repository_id)
    end
    false
  end

  # Return the list of valid repositories
  def valid_repository_ids
    @repository_ids.select { |repo_id| valid_repository?(repo_id) }
  end

  private

  memoize def disable_starred_repo_validation?
    @user.feature_flag_enabled?(:disable_starred_repo_validation, default: false)
  end

  def repo_exists?(repository_id)
    return false unless repository_id
    active_repository_ids.include?(repository_id)
  end

  def active_repository_ids
    @_active_repository_ids ||= repository_ids_and_owner_ids_and_active.filter_map do |id, _, active|
      id if active
    end
  end

  def owner_ids_and_ids
    @_owner_ids_and_ids ||= repository_ids_and_owner_ids_and_active.map do |id, owner_id|
      [owner_id, id]
    end
  end

  def repository_ids_and_owner_ids_and_active
    @_repository_ids_and_owner_ids_and_active ||=
      Repository.where(id: @repository_ids).pluck(:id, :owner_id, :active)
  end

  def in_repo_org?(repository_id)
    @org_repo_ids ||= repository_ids_and_owner_ids_and_active.filter_map do |id, owner_id|
      id if @user.organization_ids.include?(owner_id)
    end

    @org_repo_ids.include?(repository_id)
  end

  def repo_accessible_to_user?(repository_id)
    @accessible_repo_ids ||= Set.new(@user.associated_repository_ids(min_action: :read, repository_ids: @repository_ids))
    @accessible_repo_ids.include?(repository_id)
  end

  def repo_starred_by_user?(repository_id)
    starred_repository_ids.include?(repository_id)
  end

  def block_between_users?(repository_id)
    block_relationship_repository_ids.include?(repository_id)
  end

  def block_relationship_repository_ids
    return @block_relationship_repository_ids if defined?(@block_relationship_repository_ids)
    owner_id_to_repo_ids_map = Hash.new { |hash, key| hash[key] = [] }
    owner_ids_and_ids.each do |owner_id, id|
      owner_id_to_repo_ids_map[owner_id] << id
    end
    blockable_owner_ids = owner_id_to_repo_ids_map.keys.each_slice(BATCH_SIZE).flat_map do |owner_id_slice|
      IgnoredUser.connection.select_values(Arel.sql(<<-SQL, this_user_id: @user.id, repo_owner_ids: owner_id_slice))
        (SELECT user_id AS id FROM ignored_users
        WHERE ignored_id = :this_user_id AND user_id IN (:repo_owner_ids))
        UNION ALL
        (SELECT ignored_id AS id FROM ignored_users
        WHERE ignored_id IN (:repo_owner_ids) AND user_id = :this_user_id)
      SQL
    end.uniq
    @block_relationship_repository_ids = blockable_owner_ids.each_with_object([]) do |user_id, repo_ids|
      if owner_id_to_repo_ids_map.key?(user_id)
        repo_ids.concat(owner_id_to_repo_ids_map[user_id])
      end
    end
  end

  def starred_repository_ids
    @_starred_repository_ids ||= @user.starred_repository_ids(repo_ids: @repository_ids)
  end

  def repo_forked_by_user?(repository_id)
    repository_parent_ids.include?(repository_id)
  end

  def repository_parent_ids
    @_repository_parent_ids ||=
      Repository.where(owner_id: @user.id, parent_id: @repository_ids).pluck(:parent_id)
  end

  def repo_had_issue_created_by_user?(repository_id)
    issue_repository_ids.include?(repository_id)
  end

  def issue_repository_ids
    @issue_repository_ids ||=
      Set.new(@user.issues.distinct.pluck(:repository_id) & @repository_ids) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end
end
