# typed: strict
# frozen_string_literal: true

module ContextRegion
  class BasicCrumb < Crumb
    sig { override.returns(String) }
    def label
      options[:label] || ""
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      options[:path_name]
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      options[:path_args] || []
    end

    sig { override.returns(T.nilable(String)) }
    def path
      options[:path]
    end

    sig { override.returns(Crumb) }
    def parent
      options[:parent] || super
    end
  end
end
