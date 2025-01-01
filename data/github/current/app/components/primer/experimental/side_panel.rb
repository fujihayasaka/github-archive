# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    class SidePanel < Primer::Component
      renders_many :lists, lambda { |**system_arguments|
        Primer::Experimental::SidePanel::NavList.new(classes: "ActionList", **system_arguments)
      }
      renders_one :footer_list, lambda { |**system_arguments|
        Primer::Beta::NavList.new(classes: "ActionList", **system_arguments)
      }
      renders_one :header, Primer::Box

      # By default, the side panel will show the trigger (icon, avatar, etc) in its header,
      # but a custom octicon can be provided to override this.
      renders_one :header_octicon, -> (icon) { Primer::Beta::Octicon.new(icon: icon, size: :medium) }

      renders_one :footer, Primer::BaseComponent
      renders_one :spinner, -> () { Primer::Beta::Spinner.new(size: :small) }

      # Provide an octicon or avatar which will be used as the content for the panel's dialog button
      renders_one :trigger, types: {
        icon: lambda { |**system_arguments|
          Primer::Beta::Octicon.new(size: :medium, **system_arguments)
        },
        avatar: lambda { |**system_arguments|
          Primer::Beta::Avatar.new(**T.unsafe({ src: "", alt: "", size: 32, **system_arguments }))
        }
      }

      # Use this slot for custom content that needs to sit below the side panel's lists,
      # but still within the side panel's scrollable body
      renders_many :body_items, lambda { |component_klass: Primer::BaseComponent, **system_arguments|
        component_klass.new(**system_arguments)
      }

      def initialize(title:, position:, trigger_arguments: {}, **system_arguments)
        @title = title
        @trigger_arguments = trigger_arguments

        system_arguments[:title] = title
        system_arguments[:position] = position

        system_arguments[:size] ||= :small
        system_arguments[:visually_hide_title] ||= true
        @system_arguments = system_arguments
      end

      def trigger_button_args
        default_button_args = {
          scheme: :invisible,
          p: 0,
          aria: { label: "Open menu" },
        }

        default_button_args.merge(@trigger_arguments)
      end
    end
  end
end
