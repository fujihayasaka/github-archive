# typed: false
# frozen_string_literal: true

module Issue::ProjectsDependency
  extend ActiveSupport::Concern

  included do
    has_many :cards, -> { includes(:project) },
      as: :content,
      class_name: "ProjectCard"
    destroy_dependents_in_background :cards

    has_many :project_columns, -> { includes(:project) },
      through: :cards,
      source: :column

    has_many :projects, through: :cards
  end

  # ProjectCards related to this issue that are visible to the user
  # Also loads the related Projects and ProjectColumns
  def visible_cards_for(viewer)
    return ProjectCard.none unless associated_cards.present? && readable_by?(viewer)

    scope = associated_cards(only_for_enabled_projects: true).includes(:column)

    return scope if scope.empty?

    # If the owner is an org, or the owner is a user and the viewer has
    # access to their projects, show the issue's repo's owner's projects.
    visible_account_projects = repository.owner.visible_projects_for(viewer)
    scope = scope.joins(:project).merge(Project.owned_by_repository)
      .or(scope.where(project_id: visible_account_projects))

    scope
  end

  # Public: Return ProjectCards related to this Issue.
  #
  # only_for_enabled_projects - restrict results to cards
  #   associated with projects that are not disabled in any of the three
  #   ways it's possible to disable a project (default false).
  #
  # Returns ProjectCard::ActiveRecord_Relation for the matching cards.
  def associated_cards(only_for_enabled_projects: false)
    projects_scope = projects

    if only_for_enabled_projects
      projects_scope = projects_scope.owner_projects_enabled
    end

    valid_project_ids = projects_scope
                          .pluck(:owner_type, :owner_id, :id)
                          .filter_map do |(owner_type, owner_id, id)|
                            # Project is owned by the same repository as the issue
                            next id if owner_type == "Repository" && owner_id == repository_id

                            # Project is owned by the same user/org as the issue's repository
                            next id if (owner_type == "Organization" || owner_type == "User") && owner_id == repository.owner_id
                          end

    cards.where(project_id: valid_project_ids)
  end

  # Projects related to this issue that are visible to the user.
  def visible_projects_for(viewer)
    Project.where(id: visible_cards_for(viewer).select(:project_id))
  end

  # Public: Projects that this user could add this issue to. Includes projects
  # that this issue is already in.
  #
  # adder - User wanting to add this issue to projects.
  #
  # Returns an array of projects.
  def potential_projects_for(adder, ids: :all)
    scopes = []

    if ids == :all || ids.any?
      # If the user can write to the issue's repository, all of its projects
      # are valid.
      if repository.writable_by?(adder)
        scopes << repository.projects
      end

      # If the issue's repository is owned by a user or org, any of its projects
      # that the user can write to are valid.
      if repository.owner.is_a?(User)
        scopes << repository.owner.writable_projects_for(adder)
      end

      if ids.is_a?(Array)
        scopes = scopes.map { |scope| scope.where(id: ids) }
      end
    end

    scopes.map(&:to_a).flatten.uniq
  end

  def project_workflow_review_triggers?
    projects.joins(:project_workflows)
      .where(project_workflows: { trigger_type: ProjectWorkflow::REVIEW_TRIGGERS })
      .exists?
  end
end
