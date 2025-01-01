# typed: strict
# frozen_string_literal: true

module ContextRegion
  class MemexesIndexCrumb < Crumb
    sig { override.returns(String) }
    def label
      "Projects"
    end

    sig { override.returns(Crumb) }
    def parent
      UserCrumb.new(object)
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      case object
      when Organization
        :org_projects_beta_path
      when User
        :user_projects_path
      end
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object]
    end
  end
end
