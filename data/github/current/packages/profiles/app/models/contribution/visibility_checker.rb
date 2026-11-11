# typed: true
# frozen_string_literal: true

class Contribution::VisibilityChecker
  OWNER_LOOKUP_BATCH_SIZE = 500

  def initialize(user:, viewer:, subject_map:)
    @user = user
    @viewer = viewer
    @subject_map = subject_map

    fetch_repository_metadata
  end

  # Public: Is the subject valid to show
  #
  # Returns a boolean
  def valid?(subject_type, subject_id)
    if subject_type == "Repository"
      does_repository_exist?(subject_id) && !is_repository_orphaned?(subject_id)
    else
      true
    end
  end

  # Public: Given an array of repository ids, only return valid repository ids
  # that the user has access to if skip_restricted is true.
  #
  # repository_ids  - An array of Repository IDs to check against
  # skip_restricted - A boolean when set to true, tells the method to skip restricted
  #                   repositories and only return ones user has access to
  #
  # Returns an array of repository ids
  def valid_repository_ids(repository_ids:, skip_restricted:)
    non_orphaned_repository_ids = @all_repository_ids - orphaned_repository_ids
    filtered_repository_ids = non_orphaned_repository_ids & repository_ids

    if skip_restricted
      unrestricted_repository_ids(filtered_repository_ids)
    else
      filtered_repository_ids
    end
  end

  # Public: Is the subject restricted for the viewer?
  #
  # Returns a Boolean
  def restricted?(subject_type, subject_id)
    case subject_type
    when "Repository" then repository_restricted?(subject_id)
    when "Organization" then organization_restricted?(subject_id)
    when "EnterpriseContribution" then enterprise_contribution_restricted?(subject_id)
    when "User" then user_contribution_restricted?(subject_id)
    else true
    end
  end

  private

  # Private: Bulk fetch metadata for all associated repositories.
  # Repositories that are disabled, spammy, or deleted are filtered out.
  def fetch_repository_metadata
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    scope = Repository.where(id: associated_repository_ids)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
    scope = scope.filter_spam_and_disabled_for(@viewer)
    scope = scope.active
    scope = scope.pluck(:id, :owner_id, :public)

    @all_repository_ids = scope.map { |id, _owner_id, _is_public| id }
    @public_repository_ids = scope.map { |id, _owner_id, is_public| id if is_public }.compact
    @filtered_repository_ids = scope.map(&:first)
    @repository_owner_map = scope.map { |id, owner_id| [id, owner_id] }.to_h
  end

  # Private: All of the subjects that are repositories
  #
  # Returns Array[repository_ids]
  def associated_repository_ids
    @subject_map.fetch("Repository", []).uniq
  end

  def is_repository_orphaned?(repository_id)
    orphaned_repository_ids.include?(repository_id)
  end

  def does_repository_exist?(repository_id)
    @all_repository_ids.include?(repository_id)
  end

  def orphaned_repository_ids
    return @orphaned_repository_ids if defined?(@orphaned_repository_ids)

    deleted_owner_ids = @repository_owner_map.values.each_slice(OWNER_LOOKUP_BATCH_SIZE).flat_map do |batch|
      batch - User.where(id: batch).pluck(:id)
    end

    @orphaned_repository_ids = @repository_owner_map.filter_map do |repo_id, owner_id|
      repo_id if deleted_owner_ids.include?(owner_id)
    end
  end

  # Private: Is the repository visible to the viewer?
  #
  # Repositories are restricted if:
  # - the repo is disabled and viewer is not staff
  # - the repo is spammy and viewer is not staff or owner
  # - the repo is deleted
  # - the repo is private and not accessible by the viewer
  #
  # Returns a Boolean
  def repository_restricted?(repository_id)
    return false if @public_repository_ids.include?(repository_id)

    !repo_ids_viewer_can_access.include?(repository_id)
  end

  # Private: Given a array of repository ids, returns only repository
  # ids that are unrestricted
  #
  # Repositories are restricted if:
  # - the repo is disabled and viewer is not staff
  # - the repo is spammy and viewer is not staff or owner
  # - the repo is deleted
  # - the repo is private and not accessible by the viewer
  #
  # Returns an array of repository_ids
  def unrestricted_repository_ids(repository_ids)
    repository_ids & (@public_repository_ids + repo_ids_viewer_can_access.to_a)
  end

  # Private: The repository IDs the viewer has access to.
  #
  # Returns a Set of Fixnums
  def repo_ids_viewer_can_access
    @repo_ids_viewer_can_access ||= if @viewer
      Set.new(@viewer.associated_repository_ids(min_action: :read, repository_ids: @filtered_repository_ids))
    else
      Set.new
    end
  end

  # Private: Is the organization restricted for the viewer?
  #
  # Returns a Boolean
  def organization_restricted?(organization_id)
    !user_public_org_ids.include?(organization_id) && !viewer_org_ids.include?(organization_id)
  end

  # Private: The IDs of the organizations the user is a publicized member of.
  #
  # Returns a Set of Fixnums
  def user_public_org_ids
    @user_public_org_ids ||= Set.new(@user.public_organizations.pluck(:id))
  end

  # Private: The IDs of the viewer's organizations.
  #
  # Returns a Set of Fixnums
  def viewer_org_ids
    @viewer_org_ids ||= @viewer ? Set.new(@viewer.organizations.pluck(:id)) : Set.new
  end

  # Private: Is the enterprise contribution visible to the viewer?
  #
  # These contributions are only visible to the user themself
  #
  # Returns true if user is the viewer
  def enterprise_contribution_restricted?(enterprise_contribution_id)
    enterprise_contribution_user_map[enterprise_contribution_id] != @viewer&.id
  end

  # Private: Fetch EnterpriseContributions and associated user_ids.
  #
  # Returns Hash[Integer] => Integer
  def enterprise_contribution_user_map
    return @enterprise_contribution_user_map if defined?(@enterprise_contribution_user_map)

    enterprise_contribution_ids = @subject_map.key?("EnterpriseContribution") ? @subject_map["EnterpriseContribution"].uniq : []
    @enterprise_contribution_user_map = EnterpriseContribution.where(id: enterprise_contribution_ids).pluck(:id, :user_id).to_h
  end

  # Private: Is the user contribution visible to the viewer?
  #
  # Returns a Boolean
  def user_contribution_restricted?(subject)
    # The only contribution with subject type User is JoinedGitHub which is
    # visible to all viewers.
    false
  end
end
