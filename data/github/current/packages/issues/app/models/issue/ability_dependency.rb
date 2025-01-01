# typed: true
# frozen_string_literal: true

module Issue::AbilityDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Issue }

  class_methods do
    # Returns issue IDs that the viewer is authorized to see.
    #
    # viewer - User
    # authorizables - Array<Issue::Authorizable>
    #
    # Returns Array<Integer>
    def visible_ids_for(viewer:, authorizables:)
      if (Rails.env.development? || Rails.env.test?) &&
        (non_authorizable = authorizables.find { |a| !a.is_a?(Issue::Authorizable) })

        Kernel.raise ArgumentError.new "expected Issue::Authorizable but found #{non_authorizable.class}"
      end

      visible_ids_for_viewer(viewer, authorizables)
    end

    # Returns Issues that the viewer is authorized to see.
    #
    # viewer - User
    # authorizables - Array<Issue::Authorizable>
    #
    # Returns Array<Issue>
    def visible_for(viewer:, authorizables:)
      T.bind(self, T.class_of(Issue))
      where(id: visible_ids_for(viewer: viewer, authorizables: authorizables))
    end

    # Public: Filter out issues from the given list that the viewer can't see.
    #
    # issue_ids - A list of issue ids that are being accessed.
    # viewer - The viewer (usually a User) trying to access the given issues (optional).
    # issue_ids_by_private_repo_id - Optional Hash where each key is a private repository ID and
    #   each value is an array of issue IDs from `issue_ids` that belong to that private repo.
    #   Consumers can provide this argument as an optimization when `issue_ids` is large but all of
    #   its entries are likely to come from just a small number of repos. It is assumed that any ID
    #   in `issue_ids` that does not appear in `issue_ids_by_private_repo_id` is from a public repo.
    #
    # Returns a Array<Integer>
    def legacy_visible_ids_for(issue_ids, viewer: nil, issue_ids_by_private_repo_id: nil)
      T.bind(self, T.class_of(Issue))

      return legacy_visible_ids_for_viewer(issue_ids, viewer, issue_ids_by_private_repo_id: issue_ids_by_private_repo_id) if viewer

      filter_for_public_repos_ids(issue_ids)
    end

    # Public: Build a scope that filters out issues from the given list that the viewer can't see.
    #
    # issue_ids - A list of issue ids that are being accessed.
    # viewer - The viewer (usually a User) trying to access the given issues (optional).
    # issue_ids_by_private_repo_id - Optional Hash where each key is a private repository ID and
    #   each value is an array of issue IDs from `issue_ids` that belong to that private repo.
    #   Consumers can provide this argument as an optimization when `issue_ids` is large but all of
    #   its entries are likely to come from just a small number of repos. It is assumed that any ID
    #   in `issue_ids` that does not appear in `issue_ids_by_private_repo_id` is from a public repo.
    #
    # Returns a ActiveRecord::Relation
    def legacy_visible_for(issue_ids, viewer: nil, issue_ids_by_private_repo_id: nil)
      T.bind(self, T.class_of(Issue))

      if viewer
        where(
          id: legacy_visible_ids_for_viewer(
            issue_ids,
            viewer,
            issue_ids_by_private_repo_id: issue_ids_by_private_repo_id
          )
        )
      else
        filter_for_public_repos(issue_ids)
      end
    end

    # Given a list of authorizables, return the subset of issue IDs that the viewer can see.
    private def visible_ids_for_viewer(viewer, authorizables)
      repo_ids = authorizables.map(&:repository_id).compact.uniq
      public_repo_ids = Repository.where(id: repo_ids, public: true).pluck(:id)
      non_public_repo_ids = repo_ids - public_repo_ids

      authorizables_by_repo_id = authorizables.group_by(&:repository_id)

      # For anonymous viewers, we can stop here and return just the public issue ids.
      return public_repo_ids.flat_map { |id| authorizables_by_repo_id[id]&.map(&:issue_id) }.compact if viewer.nil?

      # Add issues from repositories that are:
      # - public
      # - non-public that the viewer has been granted access to
      # - that have been unlocked for the user
      # - that the user can access via organization membership (accounting for guest-collaborators)
      viewable_repo_ids =
        public_repo_ids |
        viewer.associated_repository_ids(repository_ids: non_public_repo_ids) |
        viewer.unlocked_repository_ids |
        viewer.internal_repo_ids

      viewable_repo_ids.flat_map { |id| authorizables_by_repo_id[id]&.map(&:issue_id) }.compact
    end

    private def legacy_visible_ids_for_viewer(issue_ids, viewer, issue_ids_by_private_repo_id: nil)
      # All issue_ids belong to public repositories.
      return issue_ids if !issue_ids_by_private_repo_id.nil? && issue_ids_by_private_repo_id.blank?

      issue_ids_by_private_repo_id ||= Hash.new { |hash, key| hash[key] = [] }
      private_repo_ids = issue_ids_by_private_repo_id.keys
      visible_issue_ids = []

      if issue_ids_by_private_repo_id.present?
        visible_issue_ids = issue_ids - issue_ids_by_private_repo_id.values.flatten
      else
        issues = Issue.where(id: issue_ids).pluck(:id, :repository_id)
        repos = Repository.where(id: issues.map(&:second).uniq).pluck(:id, :public)
        public_repositories_by_id = repos.to_h
        issues.each do |issue_id, repository_id|
          if public_repositories_by_id[repository_id]
            visible_issue_ids << issue_id
          else
            # Came across issues with non-existent repos, checking to ensure repo exists for issues
            issue_ids_by_private_repo_id[repository_id] << issue_id if public_repositories_by_id.has_key?(repository_id)
          end
        end
      end

      private_repo_ids = issue_ids_by_private_repo_id.keys
      accessible_private_repo_ids = viewer.associated_repository_ids(
        repository_ids: private_repo_ids
      )

      accessible_private_repo_ids.each do |repo_id|
        visible_issue_ids += issue_ids_by_private_repo_id[repo_id]
      end
      remaining_inaccessible_repo_ids = private_repo_ids - accessible_private_repo_ids
      return visible_issue_ids if remaining_inaccessible_repo_ids.empty?

      unlocked_repo_ids = viewer.unlocked_repository_ids & remaining_inaccessible_repo_ids
      unlocked_repo_ids.each do |repo_id|
        visible_issue_ids += issue_ids_by_private_repo_id[repo_id]
      end
      visible_issue_ids
    end
  end

  # Public: Can this issue be read by the specified actor?
  #
  # actor - The actor (usually a User) trying to read the issue.
  #
  # Returns a boolean.
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  # Public: Can this issue be read by the specified actor?
  #
  # actor - The actor (usually a User) trying to read the issue.
  #
  # Same as the readable_by? method above, but returns Promise<bool>
  def async_readable_by?(actor)
    # This issue must belong to an existing repo.
    async_repository.then do |repository|
      next false unless repository

      if pull_request_id
        # The actor must be able to read pull requests on this issue's repository.
        repository.resources.pull_requests.async_readable_by?(actor)
      else
        # The actor must be able to read issues on this issue's repository.
        repository.resources.issues.async_readable_by?(actor)
      end
    end
  end

  def async_visible_and_readable_by?(actor)
    self.async_pull_request.then do |pull_request|
      source = pull_request ? pull_request : self
      source.async_hide_from_user?(actor).then do |hide_from_user|
        if hide_from_user
          Promise.resolve(false)
        else
          async_readable_by?(actor)
        end
      end
    end
  end

  def subscribable_by?(user)
    super && readable_by?(user)
  end

  def can_modify?(user)
    return false if user.nil?
    return false if T.must(repository).archived?
    return true if self.user == user

    T.must(repository).pushable_by?(user)
  end

  # Public: Get all the IDs of users with privileged access to this issue.
  #
  # Note: "Privileged access" is an Abilities term that refers to access gained
  # through any method other than the repository being public. A random user
  # who can see a public repository doesn't have privileged access to it, but
  # if they're added to a team that grants access to the repository (even if
  # it's still just read-only access), they now have privileged access to it.
  #
  # Returns an Array of Integers.
  def user_ids_with_privileged_access(actor_ids_filter: nil)
    return [] if repository.nil?

    user_ids = T.must(repository).user_ids_with_privileged_access(min_action: :read, actor_ids_filter: actor_ids_filter)

    # The issue's author has privileged access if they're still able to read
    # the issue's repository.
    user_ids |= [user_id] if T.must(repository).readable_by?(user)

    user_ids
  end

  # Public: Fetches user ids that have read access to the repository.
  #
  # User ids are fetched from the repository's organization members and the repository members.
  #
  # In contrast to `user_ids_with_privileged_access`, this method also includes organization members. This allows
  # to fetch and assign users to issues that are not directly associated with the repository. It's the case for
  # organizations with internal repositories, where users are members of the organization but not necessary members
  # of the repository.
  #
  # Please note: It fixes the customer report described in https://github.com/github/issues/issues/8930.
  #              The fix is behind a feature flag and will be enabled for specific customers only (to verify the fix).
  #              At some point, this check should be replaced with Authzd.
  #
  # Returns an Array of user ids which includes:
  #   - organization members with read access to the repo
  #   - repository members with read access to the repo
  def user_ids_with_repo_read_access
    return [] unless self.repository&.feature_enabled?(:available_assignee_ids_with_repo_read_access)
    return [] unless repository = self.repository
    return [] unless repository.organization_id

    user_ids = Platform::Loaders::ActiveRecord.load(::Organization, repository.organization_id).then do |organization|
      T.must(organization).async_business.then do
        org_members = repository.internal? ? T.must(organization).members(action: :read) : []
        (org_members.map(&:id) | repository.all_user_ids).uniq
      end
    end

    user_ids.sync
  end
end
