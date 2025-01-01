# typed: true
# frozen_string_literal: true

class AchievementRepositoryList
  def initialize(repositories:)
    @repositories = repositories
  end

  def self.none
    new(repositories: [])
  end

  attr_reader :repositories

  alias_method :flatten_as, :repositories

  def platform_type_name
    self.class.name
  end

  def filter
    return self.class.none if repositories.empty?

    ok_repositories = repositories.select { |repository| yield repository }
    self.class.new(repositories: ok_repositories)
  end

  def filter_promise
    return Promise.resolve(self.class.none) if repositories.empty?

    promises = repositories.map do |repository|
      promise = yield repository
      promise.then { |ok| [repository, ok] }
    end
    Promise.all(promises).then do |results|
      ok_repositories = results.select { |_, ok| ok }.map { |repository, _| repository }
      self.class.new(repositories: ok_repositories)
    end
  end
end
