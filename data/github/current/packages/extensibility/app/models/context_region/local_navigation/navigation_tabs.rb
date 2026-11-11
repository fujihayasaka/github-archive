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

      sig { override.returns(T.nilable(String)) }
      def turbo_frame
        nil
      end

      sig { returns(T::Boolean) }
      def react_global_nav_enabled?
        FeatureFlag.vexi.enabled?(:global_nav_react, current_user, default: false)
      end

      private

      # Needs to be overridden in subclasses, returns the entity name used in Datadog metric keys
      sig { abstract.returns(String) }
      def entity_name; end

      sig { params(tab_name: Symbol, additional_tags: T::Array[String], block: T.untyped).returns(T.untyped) }
      def record_tab_timing(tab_name, additional_tags = [], &block)
        tags = [
          "tab:#{tab_name}",
          "logged_in:#{current_user.present?}"
        ] + additional_tags

        metric_name = "navigation_tabs.#{entity_name}.tab_generation"

        GitHub.dogstats.distribution_time("#{metric_name}.dist", tags: tags, &block)
      end
    end
  end
end
