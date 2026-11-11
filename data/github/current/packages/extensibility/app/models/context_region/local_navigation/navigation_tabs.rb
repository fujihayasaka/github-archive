# typed: strict
# frozen_string_literal: true

module ContextRegion
  module LocalNavigation
    # Base class for entity-specific NavigationTabs classes (Team, User, Organization, Business)
    class NavigationTabs
      extend T::Helpers
      abstract!

      include NavigationTabsInterface

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { params(current_user: T.nilable(User), opts: T.untyped).void }
      def initialize(current_user: nil, **opts)
        @current_user = current_user
      end

      # TODO: Return plain hash here, and create a separate method to return Site::Header::UnderlineNavTab objects
      sig { override.returns(T::Array[Site::Header::UnderlineNavTab]) }
      def tabs
        []
      end

      sig { params(tab_id: Symbol).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def tab_metadata(tab_id)
        nil
      end

      sig { override.returns(T.nilable(String)) }
      def tab_counts_url
        nil
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def popover
        nil
      end

      sig { returns(T::Boolean) }
      def react_global_nav_enabled?
        FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)
      end
    end
  end
end
