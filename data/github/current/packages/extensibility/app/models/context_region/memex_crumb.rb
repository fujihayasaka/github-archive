# typed: true
# frozen_string_literal: true

module ContextRegion
  class MemexCrumb < Crumb
    def label
      object.title
    end

    def prefix_octicon
      :table
    end

    def parent
      MemexesIndexCrumb.new(object.owner)
    end

    def path_name
      case object.owner
      when Organization
        :show_org_memex_path
      when User
        :show_user_memex_path
      end
    end

    def path_args
      [object.owner, object.number]
    end

    def octicon
      :lock unless object.public?
    end

    def label_classes
      "js-context-region-label"
    end
  end
end
