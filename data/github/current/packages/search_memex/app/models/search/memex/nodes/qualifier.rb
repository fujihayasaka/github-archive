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

        sig(:final) { override.returns(String) }
        def query_string
          prefix = @exclude ? "-" : ""
          "#{prefix}#{slug}:#{values.join(',')}"
        end

        sig { params(parsed_qualifier: T::Hash[T.untyped, T.untyped]).void }
        def initialize(parsed_qualifier)
          # The slug here is intended to match one of two types of thing:
          #
          # 1. In the case of qualifier that references a Field, this is meant to match the
          # `memex_project_column.name_slug` database column (which is downcased on save)
          #
          # 2. A special qualifier like `:no`, `:has`, or `:reason`, which are hard-coded as
          # lowercase symbols in the AST.
          #
          # Hence we downcase the keyword from the parsed qualifier to allow case-insensitive matching against any
          # type of slug.
          @slug = T.let(parsed_qualifier[:keyword].downcase.to_sym, Symbol)

          @values = T.let(parsed_qualifier[:values].compact, T::Array[String])
          @exclude = T.let(parsed_qualifier[:exclude], T::Boolean)
        end

        sig { returns(T::Boolean) }
        def negated? = slug == :no ? !@exclude : @exclude
      end
    end
  end
end
