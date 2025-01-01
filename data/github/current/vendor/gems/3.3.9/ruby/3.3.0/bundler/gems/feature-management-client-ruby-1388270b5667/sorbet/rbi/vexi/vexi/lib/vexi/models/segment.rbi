# frozen_string_literal: true
# typed: strict

module Vexi
  # Segment represents a segment.
  class Segment
    extend T::Sig
    extend T::Helpers

    include Entity

    sig { params(name: String).void }
    attr_writer :name

    sig { returns(ActorCollection) }
    attr_accessor :actors

    sig { params(name: String, actors: ActorCollection).void }
    def initialize(name, actors: HashActorCollection.new({})); end

    sig { override.returns(String) }
    def name; end

    sig { params(name: String).returns(Segment) }
    def self.create_default(name); end

    sig { params(h: T::Hash[String, T.untyped]).returns(Segment) }
    def self.from_hash(h); end

    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash; end

    sig { params(other: T.untyped).returns(T::Boolean) }
    def ==(other); end
  end
end
