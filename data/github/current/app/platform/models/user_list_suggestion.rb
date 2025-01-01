# typed: true
# frozen_string_literal: true

class Platform::Models::UserListSuggestion
  include GitHub::Relay::GlobalIdentification

  def self.load_from_global_id(id)
    new(name: id)
  end

  def self.to_global_id(name:)
    new(name: name).global_relay_id
  end

  attr_reader :name

  def initialize(name:)
    @name = name.to_s.dup.force_encoding("utf-8")
  end

  def global_id
    "#{name}"
  end
end
