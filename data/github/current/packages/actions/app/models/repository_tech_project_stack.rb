# typed: true
# frozen_string_literal: true

class RepositoryTechProjectStack < ApplicationRecord::Repositories
  belongs_to :tech_stack_name
  belongs_to :repository_tech_project
end
