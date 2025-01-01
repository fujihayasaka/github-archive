# typed: true
# frozen_string_literal: true

class Archived::ProjectRepositoryLink < ApplicationRecord::Domain::Projects
  include Archived::Base

  belongs_to :project, class_name: "Archived::Project"
  belongs_to :repository, class_name: "Repository"
end
