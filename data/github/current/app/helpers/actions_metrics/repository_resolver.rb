# typed: true
# frozen_string_literal: true

module ActionsMetrics::RepositoryResolver
  def resolve_repos(items)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    repository_ids = items.pluck(:repository_id).uniq.to_a.compact
    return unless repository_ids&.length > 0

    repositories = Array.new
    repositories = Repository.where(id: repository_ids)
    repository_map = repositories.index_by { |r| r.id }

    # add repo information to each item
    items.each do |item|
      repo = repository_map[item[:repository_id]]
      unless repo.nil?
        item[:repository] = {
          id: repo.id,
          name: repo.name,
          public: repo.public?,
          url: "/#{repo.name_with_display_owner}"
        }
      end
    end

    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = (end_time - start_time) * 1_000
    GitHub.logger.info("resolve_repos complete", {
      "code.namespace" => "ActionsMetrics::RepositoryResolver",
      "code.function" => "resolve_repos",
      "gh.actions_metrics.repository_resolver.resolve_repos.time" => elapsed_time,
    })
    GitHub.dogstats.distribution("actions_metrics.repository_resolver.resolve_repos.dist.time", elapsed_time)
  end

  def add_repo_info(items, offset = 0)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    unless items.nil? || items.length == 0
      if Rails.env.development?
        # replace with fake repo because the repo ids wont resolve to anything
        items.each_with_index do |item, index|
          append = index + offset + 1
          item[:repository] = get_fake_repo(append)
        end
      else
        resolve_repos(items)
      end
    end
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    elapsed_time = (end_time - start_time) * 1_000
    GitHub.logger.info("add_repo_info complete", {
      "code.namespace" => "ActionsMetrics::RepositoryResolver",
      "code.function" => "add_repo_info",
      "gh.actions_metrics.repository_resolver.add_repo_info.time" => elapsed_time,
    })
    GitHub.dogstats.distribution("actions_metrics.repository_resolver.add_repo_info.dist.time", elapsed_time)
  end

  def get_fake_repo(append)
    name = "fake-repo-#{append}"
    public_val = SecureRandom.rand(0..1) == 0 ? true : false
    url = "#"

    repository = {
      name: name,
      public: public_val,
      url: url
    }
  end
end
