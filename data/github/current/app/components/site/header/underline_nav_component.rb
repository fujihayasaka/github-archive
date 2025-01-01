# typed: strict
# frozen_string_literal: true

module Site
  module Header
    class UnderlineNavComponent < Primer::Component
      include ApplicationHelper

      sig { returns(String) }
      attr_reader :label

      sig { returns(T::Array[UnderlineNavTab]) }
      attr_reader :tabs

      sig { returns(String) }
      attr_reader :tracking_label

      sig { returns(T::Array[String]) }
      attr_reader :container_classes

      sig { returns(T::Hash[Symbol, String]) }
      attr_reader :container_data_attrs

      sig { params(label: String, tabs: T::Array[UnderlineNavTab], responsive: T::Boolean, selected_link: T.nilable(Symbol), turbo_frame: T.nilable(String), tracking_label: String, container_classes: T::Array[String], container_data_attrs: T::Hash[Symbol, String]).void }
      def initialize(label:, tabs: [], responsive: true, selected_link: nil, turbo_frame: nil, tracking_label: "site/header", container_classes: [], container_data_attrs: {})
        @label = label
        @tabs = tabs
        @responsive = responsive
        @selected_link = selected_link
        @turbo_frame = turbo_frame
        @tracking_label = tracking_label
        @container_classes = container_classes
        @container_data_attrs = container_data_attrs
      end

      sig { returns(T::Boolean) }
      def render?
        tabs.present?
      end

      sig { returns(T::Boolean) }
      def responsive?
        @responsive
      end

      sig { returns(T.nilable(T::Boolean)) }
      def logged_in?
        helpers.logged_in?
      end

      sig { returns(T::Hash[Symbol, String]) }
      def turbo_attributes
        @turbo_frame ? { "data-turbo-frame": @turbo_frame } : {}
      end
    end
  end
end
