# typed: true
# frozen_string_literal: true

class Branch::SourceBranch::BranchSelectComponent < ApplicationComponent

  def initialize(repository:)
    @repository = repository
  end

  def repository
    @repository
  end

  def repository_default_branch
    @repository.default_branch
  end
end
