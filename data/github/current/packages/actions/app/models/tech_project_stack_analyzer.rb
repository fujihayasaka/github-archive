# typed: true
# frozen_string_literal: true

class TechProjectStackAnalyzer
  # This class finds the diff in a existing tech projects and analysed tech projects of a repo.
  class Diff
    def initialize(repository_id, existing_tech_projects, analysed_tech_projects)
      @repository_id = repository_id
      @existing_tech_projects = existing_tech_projects
      @analysed_tech_projects = analysed_tech_projects
      @delete_tech_projects = []
      @new_tech_projects = []
      @update_tech_projects = []
      evaluate_projects_diff
    end

    def evaluate_projects_diff
      @existing_tech_projects.each do |project|
        analysed_tech_project = @analysed_tech_projects.find { |pr| pr.path == project.path }
        if analysed_tech_project
          update_project(project, analysed_tech_project)
          @analysed_tech_projects.delete(analysed_tech_project)
        else
          delete_project(project)
        end
      end
      add_projects
    end

    def update_project(existing_tech_project, analysed_tech_project)
      existing_tech_project.update_repository_tech_project(@repository_id, analysed_tech_project)
      @update_tech_projects << existing_tech_project
    end

    def add_projects
      @new_tech_projects = @analysed_tech_projects.map do |project|
        new_project = RepositoryTechProject.new({ repository_id: @repository_id, path: project.path })
        new_project.repository_tech_project_stacks = project.stacks.map do |stack|
          RepositoryTechProjectStack.new({ stack_name_id: stack.id, size: stack.size, settings: stack.settings, repository_id: @repository_id })
        end
        new_project
      end
    end

    def delete_project(project)
      @delete_tech_projects << project.id

      project.repository_tech_project_stacks.each(&:mark_for_destruction)
    end

    def to_delete_tech_projects
      @delete_tech_projects
    end

    def to_add_tech_projects
      @new_tech_projects
    end

    def to_update_tech_projects
      @update_tech_projects
    end

  end


  # Internal: the repository this analyzer is for.
  attr_reader :repository

  # Initialize a new TechProjectStackAnalyzer for a repository.
  # repository - a Repository instance.
  def initialize(repository)
    @repository = repository
  end

  # Public: Analyze a repository's tech_project  stacks.
  #
  # Creates, updates, or removes Project analysis entries in the RepositoryTechProject and RepositoryTechProjectStack
  # table based on data retrieved from scout.
  #
  # commit_oid - oid of the commit to analyze
  #              (this is usually the tip of the default branch)
  #
  # Returns nothing.
  def analyze(commit_oid = nil)
    commit_oid ||= repository.default_oid
    if commit_oid == GitHub::NULL_OID || commit_oid.nil?
      clear_analysis
    else
      update_tech_project_analysis(commit_oid)
    end
  end

  def clear_analysis
    projects = TechStacks.new(repository).projects_with_stacks_records
    to_delete_projects_ids = projects.map { |project| project.id }.uniq

    RepositoryTechProject.transaction do
      delete_repository_tech_projects to_delete_projects_ids
    end
  end

  def update_tech_project_analysis(commit_oid)
    # get repo analysis response
    analysed_tech_projects = TechProjectStackAnalysis.tech_project_stack_analysis(repository, commit_oid)
    # get repo projects from database
    existing_tech_projects = TechStacks.new(repository).projects_with_stacks_records
    tech_stacks = analysed_tech_projects.map { |project| project.stacks.map { |stack| stack.name } }.flatten.uniq
    tech_stack_names = stack_names(tech_stacks)
    analysed_tech_projects.each do |tech_project|
      tech_project.stacks.each do |stack|
        stack.id = tech_stack_names[stack.name].id
      end
    end
    diff = Diff.new(repository.id, existing_tech_projects, analysed_tech_projects)
    to_delete_tech_projects_ids = diff.to_delete_tech_projects
    to_insert_tech_projects = diff.to_add_tech_projects
    to_update_tech_projects = diff.to_update_tech_projects

    RepositoryTechProject.transaction do
      update_or_insert_tech_projects to_insert_tech_projects + to_update_tech_projects
      delete_repository_tech_projects to_delete_tech_projects_ids
    end
  end

  private

  # Internal: find or create TechStackName records.
  #
  # names - an Array of tech stack name strings
  #
  # Returns a Hash of { "Name" => <TechStackName>, ... }
  def stack_names(names)
    names.map { |name| [name, TechStackName.lookup_by_name(name)] }.to_h
  end

  def delete_repository_tech_projects(projects_ids)
    return if projects_ids.empty?
    GitHub.dogstats.time "tech_project_stack_analyzer.time", tags: ["action:delete_repository_tech_project"] do
      RepositoryTechProject.destroy projects_ids
    end
  end

  def update_or_insert_tech_projects(projects)
    return if projects.empty?
    GitHub.dogstats.time "tech_project_stack_analyzer.time", tags: ["action:update_or_insert_tech_projects"] do
      projects.each { |project| project.save! }
    end
  end
end
