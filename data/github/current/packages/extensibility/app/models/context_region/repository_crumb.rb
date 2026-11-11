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
      object.repo_type_icon.to_sym unless object.public? && !object.fork?
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

    sig { override.params(user: T.nilable(User), current_copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User))).returns(T.nilable(ContextRegion::LocalNavigation::TabPayload)) }
    def tab_payload(user: nil, current_copilot_user: nil)
      ContextRegion::LocalNavigation::TabPayload.new(
        current_user: user,
        context_object: object,
        update_channel: user ? GitHub::WebSocket::Channels.signed_repo_settings(object, user) : nil,
        navigation_tabs: Repository::NavigationTabs.new(
          repository: object,
          current_user: user,
          tab_popovers: options[:tab_popovers] || {},
          on_repo_code_page: options[:on_repo_code_page] || false,
          current_copilot_user: current_copilot_user
        )
      )
    end
  end
end
