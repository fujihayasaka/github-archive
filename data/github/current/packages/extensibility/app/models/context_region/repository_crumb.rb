# typed: true
# frozen_string_literal: true

module ContextRegion
  class RepositoryCrumb < Crumb
    def label
      object.name
    end

    def compact_octicon
      :repo
    end

    def octicon
      object.repo_type_icon.to_sym unless object.public?
    end

    def parent
      UserCrumb.new(object.owner, hovercard: true)
    end

    def path_name
      :repository_path
    end

    def path_args
      [object]
    end

    def header_navigation_component
      Repositories::UnderlineNavComponent.new(repository: object)
    end
  end
end
