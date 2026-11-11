# typed: true
# frozen_string_literal: true

module Orgs::Teams::TeamRepositories
  # Returns a list of accessible repository ids for the current user's team, filtered to
  # ensure the user can see each repository. Repositories are sorted by name and
  # support optional query filtering.
  # This method is a drop-in replacement for connection_wrappers/team_repositories.rb, not
  # for `team.visible_repositories_for`. It supports a narrow subset of the team method's
  # behavior that is relevant to the Orgs::Teams controllers, and is carefully optimized for
  # performance on teams that have access to thousands of repositories:
  #   - avoiding large ID IN (...) queries on the repositories table
  #   - restricting user-access filtering to private repositories
  #   - skipping direct-ownership, indirect-forks and oauth checks that aren't relevant to teams pages
  #   - skipping checks for programmatic access
  def accessible_team_repository_ids_for_current_user(user, team, org, query: nil)
    return [] unless user.present?
    return @accessible_team_repository_ids_for_current_user if defined?(@accessible_team_repository_ids_for_current_user)

    org_repos_scope = ::Repository.active.where(owner: org, organization: org)
                     .filter_spam_and_disabled_for(user)

    if query
      query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
      org_repos_scope = org_repos_scope.where("repositories.name LIKE ?", "%#{query}%")
    end

    # Even with LIMIT 30, very long queries (e.g. for thousands of ids) on the repositories table
    # can be expensive, so let's pull out all the sorted ids (which is quick, pre-filtering) and then filter
    # and paginate the array of ids in-memory
    sorted_repos = org_repos_scope.sorted_by_name
                          .pluck(:id, :public)

    # Since the user-access check is more expensive, let's split up this array so we can restrict it to
    # private repo ids only (which matches the logic in connection_wrappers/team_repositories.rb)
    public_repo_ids = []
    private_repo_ids = []
    sorted_repos.each do |id, public|
      if public
        public_repo_ids << id
      else
        private_repo_ids << id
      end
    end

    # Filter out repository ids that the team does not have access to
    repo_ids_accessible_by_team = team.direct_or_inherited_repo_ids
    public_repo_ids &= repo_ids_accessible_by_team
    private_repo_ids &= repo_ids_accessible_by_team

    # Filter out repository ids that the user is not allowed to see
    sorted_repo_ids = sorted_repos.map(&:first)
    sorted_repo_ids &= (public_repo_ids + accessible_repo_ids_for_user(user, org, private_repo_ids))

    @accessible_team_repository_ids_for_current_user = sorted_repo_ids
  end

  private

  def accessible_repo_ids_for_user(user, org, private_repository_ids)
    return private_repository_ids if private_repository_ids.empty?
    return private_repository_ids if GitHub.enterprise? && user.site_admin?

    accessible_repository_ids = user.associated_repository_ids(
      repository_ids: private_repository_ids,
      include_oauth_restriction: false,
      including: [:direct, :indirect], # skip :owned, since we only care about access via team affiliation
      include_indirect_forks: false,
      include_oopfs: false,
      organization: org
    )

    if org.supports_internal_repositories? && user.business_ids.include?(org.business.id)
      accessible_repository_ids |= private_repository_ids & org.internal_repositories.ids
    end

    accessible_repository_ids
  end
end
