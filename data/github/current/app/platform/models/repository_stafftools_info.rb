# typed: true
# frozen_string_literal: true

class Platform::Models::RepositoryStafftoolsInfo
  attr_reader :repo

  def initialize(repo)
    @repo = repo
  end
end
