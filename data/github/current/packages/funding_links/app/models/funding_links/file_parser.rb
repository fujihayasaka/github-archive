# typed: true
# frozen_string_literal: true

class FundingLinks::FileParser
  def self.load(repository, path:, directory:)
    new(repository, path: path, directory: directory).parsed_yaml
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def parsed_yaml
    @parsed_yaml ||= if entry = repository.preferred_funding
      begin
        YAML.safe_load(entry.data)
      rescue Psych::SyntaxError, Psych::DisallowedClass
        nil
      end
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  private

  attr_reader :repository, :path, :directory

  def initialize(repository, path:, directory:)
    @repository = repository
    @path = path
    @directory = directory
  end
end
