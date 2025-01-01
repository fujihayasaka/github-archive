# typed: true
# frozen_string_literal: true

class Branch::SourceBranch::BranchSelectHeaderComponent < ApplicationComponent

  def initialize(repository:, show: false, show_fork_source: false)
    @repository = repository
    @show = show
    @show_fork_source = show_fork_source
  end

  def repository
    @repository
  end

  def show?
    @show
  end

  def show_fork_source?
    @show_fork_source
  end
end
