# typed: true
# frozen_string_literal: true

class PullRequestTemplate
  attr_reader :repository, :filename, :body

  def initialize(repository:, filename:, body: "")
    @repository = repository
    @filename = filename
    @body = body
  end

  def self.from_tree_entry(tree_entry)
    new(
      repository: tree_entry.repository,
      filename: tree_entry.name,
      body: tree_entry.data
    )
  end

  def self.wrap(tree_entries)
    tree_entries.map { |entry| from_tree_entry(entry) }
  end

  def async_repository
    Promise.resolve(repository)
  end
end
