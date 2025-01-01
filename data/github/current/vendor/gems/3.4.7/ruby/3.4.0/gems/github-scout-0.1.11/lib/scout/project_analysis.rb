require 'scout/project'

module Scout
  class ProjectAnalysis

    attr_reader :forced_rescan, :repo, :commit_oid

    def initialize(source, incoming_commit_oid, forced_rescan)
      @forced_rescan = forced_rescan
      @commit_oid = incoming_commit_oid
      @repo = Scout::Repository.new(source, commit_oid)
    end

    def get_repository_projects
      stacks = get_all_stacks

      fetch_projects_from_stacks(stacks)
    end

    def get_all_stacks
      stacks = repo.language_stacks
      scout_stacks = get_stacks
      stacks.delete_if{|stack| scout_stacks.any? {|scout_stack| scout_stack.name == stack.name }} + scout_stacks
    end

    private

    def get_stacks
      unless forced_rescan
        repo.load_stacks_cache
      end

      stacks = repo.stacks

      repo.update_stacks_cache

      stacks
    end

    def fetch_projects_from_stacks(stacks)
      # TODO: Project detection logic goes here
      project = Project.new(:tech_stack => stacks, :path => '/')

      [project]
    end
  end
end
