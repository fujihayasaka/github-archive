# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    # The PageHeader component is a header for a page that contains a title, some actions, and an optional back button
    class PageHeader < Primer::Component
      DEFAULT_TITLE_SIZE = :medium
      TITLE_WRAP_SIZE_MAPPINGS = {
        :large => "PageHeader-titleWrap--large",
        :subtitle => "PageHeader-titleWrap--subtitle",
        DEFAULT_TITLE_SIZE => "PageHeader-titleWrap--medium",
      }.freeze
      TITLE_WRAP_SIZE_OPTIONS = TITLE_WRAP_SIZE_MAPPINGS.keys.freeze

      # The link back to the previous page on mobile
      #
      # @param href [String] Where the parent link should lead to
      # @param label [String] What the parent link should say
      renders_one :parent_link, lambda { |href: "", label: "", **system_arguments|
        T.bind(self, Primer::Experimental::PageHeader)

        system_arguments[:classes] = class_names(
          "PageHeader-parentLink",
          system_arguments[:classes]
        )
        @parent_link_href = href
        @parent_link_label = label
      }


      # Back button on regular viewports.
      #
      # @param href [String] the link that the back button should go to
      # @param label [String] the aria-label for the button
      renders_one :back_button, lambda { |href: "", label: "", **system_arguments|
        T.bind(self, Primer::Experimental::PageHeader)

        system_arguments[:classes] = class_names(
          "PageHeader-backButton",
          system_arguments[:classes]
        )
        Primer::IconButton.new(**T.unsafe({ role: "button", icon: "arrow-left", "aria-expanded": false, "aria-label": label, tag: :a, href: href, hide: :whenNarrow, display: :flex, align_items: :center, **system_arguments })) # rubocop:disable Primer/DeprecatedComponents
      }

      # The leading visual rendered before the title.
      #
      # @param kwargs [Hash] The arguments accepted by <%= link_to_component(Primer::Beta::Octicon) %> or generic content
      renders_one :leading_visual, types: {
        icon: lambda { |**system_arguments|
          T.bind(self, Primer::Experimental::PageHeader)

          system_arguments[:classes] = class_names(
            "PageHeader-leadingVisual",
            system_arguments[:classes]
          )

          Primer::Beta::Octicon.new(**system_arguments)
        },
        content: lambda { |**system_arguments|
          T.bind(self, Primer::Experimental::PageHeader)

          system_arguments[:classes] = class_names(
            "PageHeader-leadingVisual",
            system_arguments[:classes]
          )

          Primer::BaseComponent.new(**T.unsafe({ tag: :span, **system_arguments }))
        },
      }

      # The title of the page header.
      #
      # @param kwargs [String]
      renders_one :title, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::PageHeader)

        system_arguments[:classes] = class_names(
          "PageHeader-title",
          system_arguments[:classes]
        )
        system_arguments[:tag] ||= :h3
        Primer::BaseComponent.new(**system_arguments)
      }

      # The trailing visual rendered after the title.
      #
      # @param kwargs [Hash] The arguments accepted by <%= link_to_component(Primer::Beta::Octicon) %>, <%= link_to_component(Primer::Beta::Label) %>, or generic content
      renders_one :trailing_visual, types: {
        icon: Primer::Beta::Octicon,
        label: Primer::Beta::Label,
        content: lambda { |**system_arguments|
          Primer::BaseComponent.new(**T.unsafe({ tag: :span, **system_arguments }))
        },
      }

      # The actions after the title.
      #
      # @param [Children]
      renders_one :actions, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::PageHeader)

        system_arguments[:classes] = class_names(
          "PageHeader-actions",
          system_arguments[:classes]
        )
        system_arguments[:tag] = :span
        Primer::BaseComponent.new(**system_arguments)
      }

      # The optional description after the title.
      #
      # @param [Children]
      renders_one :description, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::PageHeader)

        system_arguments[:classes] = class_names(
          "PageHeader-description",
          system_arguments[:classes]
        )
        system_arguments[:tag] = :div
        Primer::BaseComponent.new(**system_arguments)
      }

      # The optional navigation after the title.
      #
      # @param [Children]
      renders_one :navigation, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::PageHeader)

        system_arguments[:classes] = class_names(
          "PageHeader-navigation",
          system_arguments[:classes]
        )
        system_arguments[:tag] = :div
        Primer::BaseComponent.new(**system_arguments)
      }

      # @example Default
      #
      #   @code
      #     <%= render(Primer::Experimental::PageHeader.new) %>
      #
      # @example with title size
      #
      #   @code
      #     <%= render(Primer::Experimental::PageHeader.new(title_size: :large)) %>
      #
      # @param title_size [Symbol] The size of the title on a desktop device. <%= one_of(Primer::Experimental::PageHeader::TITLE_WRAP_SIZE_OPTIONS) %>
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      def initialize(title_size: DEFAULT_TITLE_SIZE, **system_arguments)
        @title_size = title_size
        @system_arguments = system_arguments

        @title_wrap_classes = class_names(
          "PageHeader-titleWrap",
          TITLE_WRAP_SIZE_MAPPINGS[fetch_or_fallback(TITLE_WRAP_SIZE_OPTIONS, title_size, DEFAULT_TITLE_SIZE)],
          system_arguments[:classes]
        )

        @system_arguments[:classes] = class_names(
          "PageHeader",
          system_arguments[:classes]
        )
      end

      def before_render
        @title_wrap_classes = class_names(
          {
            "PageHeader-titleWrap--hasBackButton": back_button.present?,
            "PageHeader-titleWrap--hasLeadingVisual": leading_visual.present?
          },
          @title_wrap_classes
        )
      end
    end
  end
end
