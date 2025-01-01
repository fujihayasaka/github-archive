# typed: true
# frozen_string_literal: true

class Archived::ProjectWorkflowAction < ApplicationRecord::Domain::Projects
  include Archived::Base
  belongs_to :project_workflow, class_name: "Archived::ProjectWorkflow"
end
