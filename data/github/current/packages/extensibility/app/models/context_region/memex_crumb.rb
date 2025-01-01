# typed: strict
# frozen_string_literal: true

module ContextRegion
  class MemexCrumb < Crumb
    sig { override.returns(String) }
    def label
      object.title
    end

    sig { override.returns(Symbol) }
    def prefix_octicon
      :table
    end

    sig { override.returns(Crumb) }
    def parent
      MemexesIndexCrumb.new(object.owner)
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      case object.owner
      when Organization
        :show_org_memex_path
      when User
        :show_user_memex_path
      end
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object.owner, object.number]
    end

    sig { override.returns(T.nilable(Symbol)) }
    def octicon
      :lock unless object.public?
    end

    sig { override.returns(T.nilable(String)) }
    def label_classes
      "js-context-region-label"
    end
  end
end
