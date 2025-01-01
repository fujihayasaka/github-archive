# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Base class for the nodes constructed when the user supplies a query of the form "slug:value1,value2".
      class Qualifier < Node
        abstract!

        sig { returns(Symbol) }
        attr_reader :slug
        alias_method :query_slug, :slug

        sig { returns(T::Array[String]) }
        attr_reader :values

        sig { params(parsed_qualifier: T::Hash[T.untyped, T.untyped]).void }
        def initialize(parsed_qualifier)
          @slug = T.let(parsed_qualifier[:keyword], Symbol)
          @values = T.let(parsed_qualifier[:values], T::Array[String])
          @exclude = T.let(parsed_qualifier[:exclude], T::Boolean)
        end

        sig { returns(T::Boolean) }
        def negated? = slug == :no ? !@exclude : @exclude
      end
    end
  end
end
