# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class Nameplate < Primer::Component
      DEFAULT_TAG = :a
      TAG_OPTIONS = [DEFAULT_TAG, :span].freeze

      DEFAULT_MARGIN = 1
      MARGIN_OPTIONS = [DEFAULT_MARGIN, 2].freeze

      DEFAULT_AVATAR_SIZE = 24

      # Required Avatar
      #
      # @param mr [Int] Space between Avatar and label.
      # @param kwargs [Hash] The same arguments as <%= link_to_component(Primer::Beta::Avatar) %>.
      renders_one :avatar, lambda { |mr: DEFAULT_MARGIN, **system_arguments|
        T.bind(self, Primer::Experimental::Nameplate)

        system_arguments[:mr] = fetch_or_fallback(MARGIN_OPTIONS, mr, DEFAULT_MARGIN)
        system_arguments[:size] ||= DEFAULT_AVATAR_SIZE
        system_arguments[:alt] = ""
        system_arguments[:"aria-hidden"] = "true"

        Primer::Beta::Avatar.new(**system_arguments)
      }

      # @example Default
      #
      #   <%= render(Primer::Experimental::Nameplate.new(label: "github", href: "#")) do |c| %>
      #     <% c.with_avatar(src: "https://github.com/github.png") %>
      #   <% end %>
      #
      # @example As a span
      #
      #   <%= render(Primer::Experimental::Nameplate.new(tag: :span, label: "github")) do |c| %>
      #     <% c.with_avatar(src: "https://github.com/github.png") %>
      #   <% end %>
      #
      # @example With description
      #
      #   <%= render(Primer::Experimental::Nameplate.new(label: "github", description: "GitHub Inc.", href: "#")) do |c| %>
      #     <% c.with_avatar(src: "https://github.com/github.png") %>
      #   <% end %>
      #
      # @param label [String] Label to be rendered beside the Avatar.
      # @param description [String] Description to be rendered below the label.
      # @param truncate [Boolean] Whether or not the label and description should be truncated on smaller screens.
      # @param tag [Symbol] <% one_of(Primer::Experimental::Nameplate::TAG_OPTIONS) %>
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      def initialize(label:, description: "", truncate: false, tag: DEFAULT_TAG, **system_arguments)
        @label = label
        @description = description
        @truncate = truncate

        @system_arguments = system_arguments
        @system_arguments[:tag] = fetch_or_fallback(TAG_OPTIONS, tag, DEFAULT_TAG)
        @system_arguments[:display] = :flex
        @system_arguments[:align_items] = :center
        @system_arguments[:font_weight] = :bold
        @system_arguments[:classes] = class_names(
          @system_arguments[:classes],
          "Truncate": truncate
        )
      end

      private

      def render?
        avatar.present?
      end

      def wrapper
        if @system_arguments[:tag] == :a
          @system_arguments.delete(:tag)
          return Primer::Beta::Link.new(**@system_arguments)
        end

        Primer::BaseComponent.new(**@system_arguments)
      end

      def label
        render(Primer::Beta::Text.new(font_weight: :bold, classes: class_names("Truncate-text": @truncate)).with_content(@label))
      end

      def description
        return unless @description.present?

        description_arguments = {
          color: :muted,
          font_size: 6,
          underline: false,
        }

        if @truncate
          description_arguments[:ml] = 0
          description_arguments[:classes] = "Truncate-text"
        end

        render(Primer::Beta::Text.new(**description_arguments).with_content(@description))
      end
    end
  end
end
