# typed: false
# frozen_string_literal: true

module GraphsHelper
  def contribution_types
    {
      "a" => "Additions",
      "d" => "Deletions",
      "c" => "Commits",
    }
  end

  def active_contribution_type
    contribution_types.include?(params[:type]) ? contribution_types[params[:type]] : "Commits"
  end

  def repository_participation_sparkline_cache_key(repository)
    ["v3:repo_participation_sparkline", repository.cache_key]
  end
end
