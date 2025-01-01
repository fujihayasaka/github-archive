# typed: true
# frozen_string_literal: true

require "securerandom"

class FlipperSession
  include GitHub::FlipperActor
  include GitHub::VexiActor

  SESSION_KEY = "_flipper_id".freeze

  def self.session_key
    SESSION_KEY
  end

  def self.generate_id
    SecureRandom.random_number(1E30.to_i)
  end

  attr_reader :id

  def initialize(id)
    @id = Integer(id)
  end

  def eql?(other)
    other.class == self.class && other.id == @id
  end
  alias_method :==, :eql?
end
