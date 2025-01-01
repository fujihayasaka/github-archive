# typed: true
# frozen_string_literal: true

class Settings::DeletedRepositoriesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :target, :deleted_repos

  def filtered_list
    return @deleted_repos if @deleted_repos.empty?
    @deleted_repos.reject { |repo| !repo.safe_to_restore || deleted_by_staff(repo) || unrestorable_repository_ids.include?(repo.id) }
  end

  def unrestoreable_list
    Repositories::Public.deleted_owned_by(@target.id) - @deleted_repos
  end

  def disclaimer_text
    "It may take up to an hour for repositories to be displayed here. You can only restore repositories that are not forks, or have not been forked."
  end

  def help_url
    "#{GitHub.help_url}/articles/restoring-a-deleted-repository"
  end

  private

  # In this situation if it's your repo, and you deleted it then you should see it, staff or not.
  # Otherwise if a staff member deleted your repo, then we should not display it as
  # repo removal by staff should only occur for abuse based reasons and we do not want it to be restorable
  def deleted_by_staff(repo)
    return false if staff_safe(repo)
    repo.deleted_by_staff?
  end

  def staff_safe(repo)
    target_is_organization? ? current_user.site_admin? : repo.deleted_by == current_user
  end

  def target_is_organization?
    @target.is_a?(Organization)
  end

  def unrestorable_repository_ids
    # There is a set of unrestorable repository ids: historically, this used the workspace relationship
    # to populate a set of ids. Going forward after this feature is enabled, the boolean prop can be used.

    unless defined? @unrestorable_repository_ids
      potential_workspace_repository_ids = []
      unrestorable_repositories = []
      @deleted_repos.each do |repo|
        potential_workspace_repository_ids << repo.id
        if FeatureFlag.vexi.enabled?(:advisory_db_unrestorable_repositories, repo, current_user, default: true) && !repo.restorable? # 100% dark shipped, defaulting to true
          unrestorable_repositories << repo.id
        end
      end
      @unrestorable_repository_ids = RepositoryAdvisory.where(workspace_repository_id: potential_workspace_repository_ids).pluck(:workspace_repository_id)
      @unrestorable_repository_ids = @unrestorable_repository_ids.concat(unrestorable_repositories)
    end

    @unrestorable_repository_ids
  end
end
