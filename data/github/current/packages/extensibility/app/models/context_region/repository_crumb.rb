# typed: strict
# frozen_string_literal: true

module ContextRegion
  class RepositoryCrumb < Crumb
    sig { override.returns(String) }
    def label
      object.name
    end

    sig { override.returns(Symbol) }
    def prefix_octicon
      :repo
    end

    sig { override.returns(T.nilable(Symbol)) }
    def octicon
      object.repo_type_icon.to_sym unless object.public?
    end

    sig { override.returns(Crumb) }
    def parent
      UserCrumb.new(object.owner, hovercard: true)
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :repository_path
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object]
    end

    sig { override.returns(Repositories::UnderlineNavComponent) }
    def header_navigation_component
      Repositories::UnderlineNavComponent.new(repository: object)
    end

    sig { override.params(user: T.nilable(User)).returns(T.nilable(ContextRegion::LocalNavigation::TabPayload)) }
    def tab_payload(user: nil)
      ContextRegion::LocalNavigation::TabPayload.new(
        current_user: user,
        context_object: object,
        navigation_tabs: Repository::NavigationTabs.new(
          repository: object,
          current_user: user
        )
      )
    end
  end
end
