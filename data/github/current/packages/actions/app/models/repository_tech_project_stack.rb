# typed: true
# frozen_string_literal: true

class RepositoryTechProjectStack < ApplicationRecord::Domain::Repositories
  belongs_to :tech_stack_name
  belongs_to :repository_tech_project
end
