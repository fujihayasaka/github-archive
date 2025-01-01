# typed: true
# frozen_string_literal: true

class Archived::Project < ApplicationRecord::Domain::Projects
  include Archived::Base

  has_many :columns, class_name: "Archived::ProjectColumn", dependent: :delete_all
  has_many :cards, class_name: "Archived::ProjectCard", dependent: :delete_all
  has_many :project_workflows, class_name: "Archived::ProjectWorkflow", dependent: :delete_all
  has_many :project_workflow_actions, class_name: "Archived::ProjectWorkflowAction", dependent: :delete_all
  has_many :project_repository_links, class_name: "Archived::ProjectRepositoryLink", dependent: :delete_all

  extend GitHub::Encoding
  force_utf8_encoding :body, :name

  def self.archive(project)
    record = super(project)

    record.update_attribute(:deleted_at, nil)

    record
  end

  def creator
    @creator ||= User.where(id: creator_id).first || User.ghost
  end

  def enqueue_restore
    RestoreProjectJob.perform_later(id)
  end

  def restore
    record = super

    if record.present?
      if record.owner_type == "Organization"
        # Restore admin-on-owner grants.
        record.owner.dependent_added(record)
      end

      record.synchronize_search_index
      record.cards.each(&:synchronize_content_search_index)
    end

    record
  end
end
