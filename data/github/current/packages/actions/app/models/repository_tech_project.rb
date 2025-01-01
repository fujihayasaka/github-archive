# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class RepositoryTechProject < ApplicationRecord::Domain::Repositories
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  belongs_to :repository
  has_many :repository_tech_project_stacks, dependent: :destroy, autosave: true

  def update_repository_tech_project(repository_id, analysed_tech_project)
    repository_tech_project_stacks.each do |stack|
      analysed_stack = analysed_tech_project.stacks.find { |st| st.id == stack.stack_name_id }
      if analysed_stack
        stack.size = analysed_stack.size
        stack.settings = analysed_stack.settings
        analysed_tech_project.stacks.delete(analysed_stack)
      else
        stack.mark_for_destruction
      end
    end

    analysed_tech_project.stacks.each do |stack|
      repository_tech_project_stacks.build({ stack_name_id: stack.id, settings: stack.settings, size: stack.size, repository_id: repository_id })
    end
  end
end
