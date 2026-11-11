# typed: true
# frozen_string_literal: true

class DependabotAnnotation < ApplicationRecord::Domain::RepositoriesActionsChecks
  self.table_name = "dependabot_autofix_annotations"

  belongs_to :check_annotation
  belongs_to :check_run
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain

  validate :matches_check_run_repository
  validate :matches_check_annotation_repository

  private

  def matches_check_run_repository
    cr = check_run
    return if cr.nil?
    if repository_id != cr.repository_id
      errors.add(:repository, "does not match the check run's repository")
    end
  end

  def matches_check_annotation_repository
    ca = check_annotation
    return if ca.nil?
    if repository_id != ca.repository_id
      errors.add(:repository, "does not match the check annotation's repository")
    end
  end
end
