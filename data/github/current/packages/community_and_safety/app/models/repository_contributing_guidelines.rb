# typed: strict
# frozen_string_literal: true

# Represents a repository's contributing guidelines
class RepositoryContributingGuidelines
  extend T::Sig

  include UrlHelper
  include GitHub::Relay::GlobalIdentification

  sig { returns(Repository) }
  attr_reader :repository

  extend Forwardable
  def_delegator :repository, :id


  sig { params(repo_id: T.any(Integer, String)).returns(RepositoryContributingGuidelines) }
  def self.find(repo_id)
    repo = Repositories::Public.find_active!(repo_id)
    RepositoryContributingGuidelines.new(repo) if repo
  end

  sig { params(repository: T.untyped).void }
  def initialize(repository)
    raise ArgumentError unless repository.is_a?(Repository)
    @repository = T.let(repository, Repository)
  end

  sig { returns(T.nilable(String)) }
  def content
    return unless repository.preferred_contributing
    @content ||= T.let(repository.preferred_contributing.data, T.nilable(String))
  end
  alias body content

  sig { returns(T.nilable(Integer)) }
  def global_id
    repository.id
  end

  sig { returns(Promise[T.untyped]) }
  def async_repository
    Promise.resolve(repository)
  end

  # Returns the relative path to the file's blob view, or nil if none exists
  sig { returns(T.nilable(String)) }
  def path
    @path = T.let(@path, T.nilable(String))
    return @path unless @path.nil?
    preferred_contributing = repository.preferred_contributing
    @path = preferred_contributing ? preferred_file_path(type: :contributing, repository: repository) : nil
  end

  # Returns the absolute URL to the file's blob view or nil if none exists
  sig { returns(T.nilable(URI::Generic)) }
  def url
    @url ||= T.let(URI.join(GitHub.url, T.must(path)), T.nilable(URI::Generic)) if path
  end

  sig { returns(String) }
  def platform_type_name
    "ContributingGuidelines"
  end
end
