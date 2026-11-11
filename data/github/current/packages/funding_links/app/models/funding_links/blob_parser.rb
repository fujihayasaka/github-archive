# typed: true
# frozen_string_literal: true

class FundingLinks::BlobParser
  class FailedToParseError < StandardError; end

  def self.load(blob:)
    new(blob).parsed_yaml
  end

  def parsed_yaml
    @parsed_yaml ||= begin
      YAML.safe_load(blob)
    rescue Psych::SyntaxError, Psych::DisallowedClass
      nil
    end
  end

  private

  attr_reader :blob

  def initialize(blob)
    @blob = blob
  end
end
