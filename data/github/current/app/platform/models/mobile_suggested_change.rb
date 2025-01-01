# typed: true
# frozen_string_literal: true

class Platform::Models::MobileSuggestedChange
  include GitHub::Relay::GlobalIdentification

  def self.load_from_global_id(id)
    path, suggestion = id.split(":", 2)
    new(suggestion: suggestion, path: path)
  end

  def self.to_global_id(suggestion:, path:)
    new(suggestion: suggestion, path: path).global_relay_id
  end

  attr_reader :path

  def initialize(suggestion:, path:)
    @suggestion = suggestion&.dup&.force_encoding("utf-8")
    @path = path
  end

  def suggestion
    @suggestion.split("\n")
  end

  def raw_suggestion
    @suggestion
  end

  def global_id
    "#{path}:#{raw_suggestion}"
  end
end
