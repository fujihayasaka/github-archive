# typed: true
# frozen_string_literal: true

# The underlying model that is used to store the curation relation between a MemexProject and organizations, repositories, and teams.

class MemexProjectLink < ApplicationRecord::Domain::Memexes

  include GitHub::Validations

  belongs_to :memex_project, required: true
  belongs_to :source, polymorphic: true, required: true

  validates :memex_project, presence: true, uniqueness: {
    scope: [:source_id, :source_type],
    message: "A link already exists between this project and the desired source.",
  }

  validates :source_id, presence: true, on: :create
  validates :source_type, presence: true, inclusion: { in: %w[Repository Team Organization] }

  scope :for_organizations, -> { where(source_type: "Organization") }

  validate :must_have_same_owner, on: :create
  validate :max_projects_for_source, on: :create
  validate :recommended_memex_project_is_template

  private

  # When a MemexProjectLink is established for an organization, the MemexProject must be a template.
  # This is because the MemexProjectLink is used to recommend a template to an organization.
  def recommended_memex_project_is_template
    return unless source_type == "Organization"
    return if memex_project&.memex_template&.active?

    errors.add(:memex_project, :expected_memex_template)
  end

  # Supports org-owned & user-owned projects.
  def must_have_same_owner
    case source_type
    when "Repository"
      errors.add(:base, "The selected project and repository must have the same owner.") unless memex_project&.owner == source&.owner
    when "Organization"
      errors.add(:base, "The selected project template must have the same owner.") unless memex_project&.owner == source
    end
  end

  def max_projects_for_source
    return unless source

    case source_type
    when "Repository"
      # Repos can only have MemexProject::MAX_REPO_CURATED_PROJECTS linked memex projects.
      if source.memex_projects.count >= MemexProject::MAX_REPO_CURATED_PROJECTS
        errors.add(:source, :exceeded_memex_project_link_limit, limit: MemexProject::MAX_REPO_CURATED_PROJECTS)
      end
    when "Organization"
      if source.memex_project_links.count >= MemexTemplate::MAX_ORGANIZATION_RECOMMENDED_TEMPLATES
        errors.add(:source, :exceeded_memex_template_link_limit, limit: MemexTemplate::MAX_ORGANIZATION_RECOMMENDED_TEMPLATES)
      end
    end
  end
end
