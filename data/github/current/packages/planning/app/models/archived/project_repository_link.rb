# typed: true
# frozen_string_literal: true

class Archived::ProjectRepositoryLink < ApplicationRecord::Domain::Projects
  include Archived::Base

  belongs_to :project, class_name: "Archived::Project"
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain class_name: "Repository"
end
