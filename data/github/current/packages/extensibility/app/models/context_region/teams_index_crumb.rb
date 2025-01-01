# typed: strict
# frozen_string_literal: true

module ContextRegion
  class TeamsIndexCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Teams"
    end

    sig { override.returns(Symbol) }
    def prefix_octicon
      :people
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :teams_path
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object]
    end

    sig { override.returns(Crumb) }
    def parent
      UserCrumb.new(object)
    end
  end
end
