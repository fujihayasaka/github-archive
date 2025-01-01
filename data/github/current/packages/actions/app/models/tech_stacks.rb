# typed: true
# frozen_string_literal: true

class TechStacks
  # Initialize Tech Stacks for a repository.
  #
  # repositories - one or more Repository instances.
  def initialize(repositories)
    @repositories = repositories
  end

  # Public: Get a list of Projects and their stacks for a repository
  # or group of repositories.
  def tech_project_stacks
    projects_with_stacks = projects_with_stacks_records

    stack_ids_set = Set.new

    projects_with_stacks.each do |project|
      stack_ids_set += project.repository_tech_project_stacks.map { |stack| stack.stack_name_id }
    end

    names_by_id = TechStackName.
      where(id: stack_ids_set).
      pluck(:id, :name).to_h

    project_array = projects_with_stacks.map do |project|
      project_mapper = RepositoryTechProjectContract.new(project.path, nil)
      project_mapper.stacks = project.repository_tech_project_stacks.map do |stack|
        RepositoryTechProjectStackContract.new(names_by_id[stack.stack_name_id], stack.size, stack.settings)
      end
      project_mapper
    end

    project_array.to_json
  end

  def projects_with_stacks_records
    GitHub.dogstats.time "tech_stack_analysis.time", tags: ["action:analysis_retrieval"] do
      RepositoryTechProject.includes(:repository_tech_project_stacks).where(repository: @repositories).to_a
    end
  end

end
