# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# This module helps fetch projects in a repo along with its respective programming stacks.
# A project is essentially a sub-tree in a repository represented by a relative path from its root.
# A Programming stack could be a language, framework, build system, or package manager and so on.
module TechProjectStackAnalysis
  # tech-stack-analysis related methods

  # Returns an Array of [ ["project.name", stacks_percentage ], ... ]
  # in descending order by percentage.
  def self.tech_projects_with_stack_percentages(repository)
    projects_array = tech_project_stacks repository
    projects_array.map { |project| [project.path, project.get_stack_percentages] }
  end

  # Analyzes the repository and update its tech project stacks
  def self.analyze_tech_project_stacks(repository)
    TechProjectStackAnalyzer.new(repository).analyze
  end

  # Internal: cache key for projects.
  def self.tech_projects_cache_key(repository)
    ["repository", repository.id, repository.pushed_at.to_i, "tech_projects", "v9"].compact.join(":")
  end

  # Retrieve a list of projects and their stacks for this repository.
  #
  # Uses a read-through cache.
  #
  # Returns an Array of Projects
  def self.tech_project_stacks(repository)
    json_response = GitHub.cache.fetch(tech_projects_cache_key(repository), stats_key: "repository_tech_projects.cache") do
      tech_projects_stacks_with_language_fallback repository
    end
    to_tech_stack_analysis_contract json_response
  end

  # Enqueue the job to analyze project stack
  def self.enqueue_analyze_tech_project_stack(id)
    RepositoryUpdateTechProjectAndStackJob.perform_later(id)
  end

  # Tech-project analysis by rpc call to scout
  def self.tech_project_stack_analysis(repository, commit_oid)
    started_at = GitHub::Dogstats.monotonic_time
    response = repository.rpc.tech_project_stacks(commit_oid, false)
    GitHub.dogstats.distribution("tech_stacks.tech_project_stack_analysis.time", GitHub::Dogstats.duration(started_at), tags: ["action:rpc.tech_project_stacks"])
    GlobalInstrumenter.instrument("tech_project_stack_analysis.repository", {
      repository: repository,
      commit_oid: commit_oid,
      tech_project_stacks: response,
    })

    response.map { |rp| RepositoryTechProjectContract.new(rp["path"], rp["tech_stack"].map { |stack| RepositoryTechProjectStackContract.new(stack["name"], stack["size"], stack["settings"]) }) }
  end

  def self.to_tech_stack_analysis_contract(json_response)
    response = JSON.parse(json_response)
    response.map do |rp| RepositoryTechProjectContract.new(rp["path"], rp["stacks"]
      .map { |stack| RepositoryTechProjectStackContract.new(stack["name"], stack["size"], stack["settings"]) })
    end
  end

  def self.tech_projects_stacks_with_language_fallback(repository)
    GitHub.dogstats.increment("tech_stacks.tech_projects_stacks_with_language_fallback.fetch", tags: ["action:fetch_tech_stacks_projects"])
    tech_stack_breakdown = TechStacks.new(repository).tech_project_stacks

    if tech_stack_breakdown == "[]"
      GitHub.dogstats.increment("tech_stacks.tech_projects_stacks_with_language_fallback.fallback", tags: ["action:take_language_fallback"])
      language_only_tech_stacks = []
      repository.language_breakdown.each do |name, size|
        language_only_tech_stacks << RepositoryTechProjectStackContract.new(name, size, nil)
      end

      tech_stack_breakdown = [RepositoryTechProjectContract.new("/", language_only_tech_stacks)].to_json if !language_only_tech_stacks.empty?
    end

    tech_stack_breakdown
  end
end
