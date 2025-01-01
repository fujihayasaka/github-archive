# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class Archived::ProjectWorkflow < ApplicationRecord::Domain::Projects
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  include Archived::Base
  has_many :project_workflow_actions, class_name: "Archived::ProjectWorkflowAction", dependent: :delete_all
  belongs_to :project, class_name: "Archived::Project"

  def creator
    @creator ||= User.where(id: creator_id).first || User.ghost
  end
end
