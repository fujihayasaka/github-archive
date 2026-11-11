# typed: true
# frozen_string_literal: true

# Represents a repository's code of conduct
# For codes of conduct generally, see code_of_conduct.rb
class RepositoryCodeOfConduct < CodeOfConduct
  attr_reader :repository
  include UrlHelper
  include GitHub::Relay::GlobalIdentification

  extend Forwardable
  def_delegator :repository, :id

  def self.find(repo_id)
    repo = Repositories::Public.find_active!(repo_id)
    RepositoryCodeOfConduct.new(repo) if repo
  end

  def initialize(repository)
    raise ArgumentError unless repository.is_a?(Repository)
    @repository = repository
    super(key)
  end

  # Detect the code of conduct from the code of conduct file's content, if present
  # Returns a string representing the code of conduct's key
  def key
    @key ||= (file && file.code_of_conduct) ? file.code_of_conduct.key : "none"
  end

  def content
    return unless repository.preferred_code_of_conduct
    @content ||= repository.preferred_code_of_conduct.data
  end
  alias body content

  def global_id
    repository.id
  end

  def async_repository
    Promise.resolve(repository)
  end

  # Returns the relative path to the file's blob view, or nil if none exists
  def path
    return @path if defined? @path
    preferred_coc = repository.preferred_code_of_conduct
    @path = preferred_coc ? preferred_file_path(type: :code_of_conduct, repository: repository) : nil
  end

  # Returns the absolute URL to the file's blob view or nil if none exists
  def url
    @url ||= URI.join(GitHub.url, path) if path
  end

  def platform_type_name
    "CodeOfConduct"
  end

  private

  def file
    return unless content && !content.blank?
    @file ||= Coconductor::ProjectFiles::CodeOfConductFile.new(content)
  end
end
