# typed: false
# frozen_string_literal: true

# Represents a link between an org-owned project and repository.
#
# To create a link, use the LinkRepositoryToProject mutation
# To remove a link, use the UnlinkRepositoryFromProject mutation
#
# Requirements:
#   - the project and repository must belong to the same organization
#   - a project can only have Project::MAX_REPOSITORY_LINKS linked repos
#   - the creating user must have access to the project *and* repository

class ProjectRepositoryLink < ApplicationRecord::Domain::Projects

  belongs_to :project
  belongs_to :repository
  belongs_to :creator, class_name: "User"

  validates :project, presence: true, uniqueness: {
    scope: :repository_id,
    message: "A link already exists between this project and repository.",
  }
  validates :repository, presence: true
  validate :actor_can_modify_repo
  validate :must_have_same_owner
  validate :max_links_per_project, on: :create

  after_commit :synchronize_project_search_index
  after_commit :track_link, on: :create
  after_commit :track_unlink, on: :destroy

  # Returns a list of repos accessible to the user matching the optional filter
  def self.linkable_repos_for(viewer:, owner:, filter: nil)
    return Repository.none unless viewer

    repos = owner.visible_repositories_for(viewer).not_archived_scope
    repos = repos.with_issues_enabled.order(:name).limit(20)
    repos = repos.with_prefix("repositories.name", filter.downcase) if filter
    repos
  end

  private

  def actor_can_modify_repo(actor: modifying_user)
    unless content_authorizer_for(user: actor).passed?
      content_authorizer_for(user: actor).errors.each do |error|
        errors.add(:base, error.message)
      end
    end
  end

  # `must_have_same_owner` supports org-owned & (eventually) user-owned projects.
  # When repo-owned projects are migrated up a level to the org or user, this
  # validation will need to be bypassed or modified prior to migrating.
  def must_have_same_owner
    errors.add(:base, "The selected project and repository must have the same owner.") unless project&.owner == repository&.owner
  end

  # Projects are limited to `Project::MAX_REPOSITORY_LINKS` linked repositories
  # We return early to avoid comparing nil to an integer if `project` is nil
  def max_links_per_project
    return unless project

    if project.linked_repositories.count >= Project::MAX_REPOSITORY_LINKS
      errors.add(:base, "Can only create #{Project::MAX_REPOSITORY_LINKS} repository links per project")
    end
  end

  def synchronize_project_search_index
    project&.synchronize_search_index
  end

  def track_link
    GitHub.dogstats.increment("project_repository_link.created", tags: [:"owner_type:#{project.owner_type}"])
  end

  def track_unlink
    if project
      GitHub.dogstats.increment("project_repository_link.deleted", tags: [:"owner_type:#{project.owner_type}"])
    end
  end

  def content_authorizer_for(user:)
    @content_authorizers ||= {}

    return @content_authorizers.fetch(user.id) if @content_authorizers.has_key?(user.id)

    @content_authorizers[user.id] = ContentAuthorizer.authorize(user, :repo, :update, repo: repository)
  end

  # The user who performed the action as set in the GitHub request context.
  # If the context doesn't contain an actor, fallback to the ghost user
  def modifying_user
    @modifying_user ||= (User.find_by_id(GitHub.context[:actor_id]) || User.ghost)
  end
end
