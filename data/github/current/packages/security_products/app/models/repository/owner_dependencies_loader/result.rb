# typed: true
# frozen_string_literal: true

class Repository::OwnerDependenciesLoader::Result
  # Public: The repositories that were loaded.
  #
  # Returns an Array of Repository records.
  attr_reader :dependencies

  def initialize(dependencies:, already_sorted:)
    @dependencies = dependencies
    @already_sorted = !!already_sorted
  end

  # Public: Were these repositories loaded in a single query such that they're sorted in the expected order,
  # or were they loaded across multiple batches that will require additional sorting for the overall list?
  #
  # Returns a Boolean.
  def already_sorted?
    @already_sorted
  end

  def dependency_ids
    dependencies.map(&:id)
  end
end
