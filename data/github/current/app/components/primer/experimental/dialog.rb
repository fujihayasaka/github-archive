# typed: strict
# frozen_string_literal: true

require "securerandom"

module Primer
  module Experimental
    # A `Dialog` is used to remove the user from the main application flow, display information, and to request action confirmation, like delete a discussion or transfer an issue to another repository.
    #
    # @accessibility
    #   - **Dialog Accessible Name**: A dialog should have an accessible name, so screen readers are aware of the purpose of the dialog when it opens.
    #   Give an accessible name setting `:title`. The accessible name will be used as the main heading inside the dialog.
    #   - **Dialog unique id**: A dialog should be unique. Give a unique id setting `:dialog_id`. If no `:dialog_id` is given, a default randomize hex id is generated.
    #
    #   The combination of both `:title` and `:dialog_id` establishes an `aria-labelledby` relationship between the title and the unique id of the dialog.
    class Dialog < Primer::Component
      DEFAULT_POSITION = :center
      POSITION_MAPPINGS = T.let({
        DEFAULT_POSITION => "Overlay-backdrop--center",
        :left => "Overlay-backdrop--side Overlay-backdrop--placement-left",
        :none => "",
      }.freeze, T::Hash[Symbol, String])
      POSITION_OPTIONS = T.let(POSITION_MAPPINGS.keys, T::Array[Symbol])

      DEFAULT_POSITION_NARROW = :inherit
      POSITION_NARROW_MAPPINGS = T.let({
        DEFAULT_POSITION_NARROW => "",
        :bottom => "Overlay-backdrop--side Overlay-backdrop--placement-bottom",
        :fullscreen => "Overlay-backdrop--full-whenNarrow",
      }.freeze, T::Hash[Symbol, String])
      POSITION_NARROW_OPTIONS = T.let(POSITION_NARROW_MAPPINGS.keys, T::Array[Symbol])

      DEFAULT_FOOTER_CONTENT_ALIGN = :end
      FOOTER_CONTENT_ALIGN_MAPPINGS = T.let({
        :start => "Overlay-footer--alignStart",
        :center => "Overlay-footer--alignCenter",
        :medium => "Overlay--height-medium",
        DEFAULT_FOOTER_CONTENT_ALIGN => "Overlay-footer--alignEnd",
      }.freeze, T::Hash[Symbol, String])
      FOOTER_CONTENT_ALIGN_OPTIONS = T.let(FOOTER_CONTENT_ALIGN_MAPPINGS.keys, T::Array[Symbol])

      DEFAULT_HEADER_VARIANT = :medium
      HEADER_VARIANT_MAPPINGS = T.let({
        DEFAULT_HEADER_VARIANT => "",
        :large => "Overlay-header--large",
      }.freeze, T::Hash[Symbol, T.untyped])
      HEADER_VARIANT_OPTIONS = T.let(HEADER_VARIANT_MAPPINGS.keys, T::Array[T.untyped])

      DEFAULT_BODY_PADDING_VARIANT = :normal
      BODY_PADDING_VARIANT_MAPPINGS = T.let({
        DEFAULT_BODY_PADDING_VARIANT => "",
        :condensed => "Overlay-body--paddingCondensed",
        :none => "Overlay-body--paddingNone",
      }.freeze, T::Hash[Symbol, String])
      BODY_PADDING_VARIANT_OPTIONS = T.let(BODY_PADDING_VARIANT_MAPPINGS.keys, T::Array[Symbol])

      DEFAULT_HEIGHT = :auto
      HEIGHT_MAPPINGS = T.let({
        DEFAULT_HEIGHT => "Overlay--height-auto",
        :xsmall => "Overlay--height-xsmall",
        :small => "Overlay--height-small",
        :medium => "Overlay--height-medium",
        :large => "Overlay--height-large",
        :xlarge => "Overlay--height-xlarge",
      }.freeze, T::Hash[Symbol, String])
      HEIGHT_OPTIONS = T.let(HEIGHT_MAPPINGS.keys, T::Array[Symbol])

      DEFAULT_WIDTH = :medium
      WIDTH_MAPPINGS = T.let({
        :small => "Overlay--width-small",
        DEFAULT_WIDTH => "Overlay--width-medium",
        :large => "Overlay--width-large",
        :xlarge => "Overlay--width-xlarge",
        :xxlarge => "Overlay--width-xxlarge",
      }.freeze, T::Hash[Symbol, String])
      WIDTH_OPTIONS = T.let(WIDTH_MAPPINGS.keys, T::Array[Symbol])

      DEFAULT_MOTION = :scale_fade
      MOTION_MAPPINGS = T.let({
        DEFAULT_MOTION => "Overlay--motion-scaleFade",
        :none => "",
      }.freeze, T::Hash[Symbol, String])
      MOTION_OPTIONS = T.let(MOTION_MAPPINGS.keys, T::Array[Symbol])

      # Optional list of buttons to be rendered.
      #
      # @param system_arguments [Hash] The same arguments as <%= link_to_component(Primer::ButtonComponent) %>.
      renders_many :buttons, lambda { |**system_arguments|
        if system_arguments[:type].present? && system_arguments[:type] == :submit
          @form_id = T.let(@form_id, T.nilable(String))
          system_arguments[:form] = @form_id
        end
        Primer::ButtonComponent.new(**system_arguments) # rubocop:disable Primer/DeprecatedComponents
      }

      # Optional button to open the dialog.
      #
      # @param system_arguments [Hash] The same arguments as <%= link_to_component(Primer::ButtonComponent) %>.
      renders_one :show_button, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::Dialog)
        system_arguments[:classes] = class_names(
          system_arguments[:classes]
        )
        @system_arguments = T.let(@system_arguments, T.nilable(T::Hash[Symbol, T.untyped]))
        system_arguments[:id] = "dialog-show-#{T.must(@system_arguments)[:id]}"
        system_arguments["data-show-dialog-id"] = T.must(@system_arguments)[:id]
        system_arguments[:data] = (system_arguments[:data] || {}).merge({ "target": "modal-dialog.show-button" })
        Primer::ButtonComponent.new(**system_arguments) # rubocop:disable Primer/DeprecatedComponents
      }

      # Required body content.
      #
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      renders_one :body, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::Dialog)
        deny_tag_argument(**system_arguments)
        system_arguments[:tag] = :div

        system_arguments[:classes] = class_names(
          system_arguments[:classes]
        )
        Primer::BaseComponent.new(**system_arguments)
      }

      # Optional include_fragment element, use this instead of body when loading dialog content on show_button
      # click or hover.
      #
      # @param system_arguments [Hash] https://github.github.io/include-fragment-element/
      renders_one :include_fragment, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::Dialog)
        deny_tag_argument(**system_arguments)
        system_arguments[:tag] = "include-fragment"
        @src = T.let(@src, T.nilable(String))
        raise ArgumentError, "missing keyword: src" if !@src
        system_arguments[:src] = @src
        system_arguments[:loading] = :lazy
        system_arguments[:classes] = class_names(
          system_arguments[:classes]
        )
        system_arguments[:data] = (system_arguments[:data] || {}).merge({ "target": "modal-dialog.include-fragment" })
        Primer::BaseComponent.new(**system_arguments)
      }

      # @example Dialog without submit or cancel buttons
      #   @description
      #     If the tooltip content provides supplementary description, set `type: :description` to establish an `aria-describedby` relationship.
      #     The trigger element should also have a _concise_ accessible label via `aria-label`.
      #   @code
      #     <%= render(Primer::Experimental::Dialog.new(
      #       title: "This is the tile of the dialog",
      #       description: "This is the description of the dialog",
      #       dialog_id: "dialog-without-buttons"
      #     )) do |c| %>
      #       <% c.with_show_button { "Show dialog" } %>
      #       <% c.with_body do %>
      #         <p>The body of the dialog</p>
      #       <% end %>
      #     <% end %>
      #
      # @example Dialog with submit or cancel buttons
      #   @description
      #     If the tooltip content provides supplementary description, set `type: :description` to establish an `aria-describedby` relationship.
      #     The trigger element should also have a _concise_ accessible label via `aria-label`.
      #   @code
      #     <%= render(Primer::Experimental::Dialog.new(
      #       title: "This is the tile of the dialog",
      #       description: "This is the description of the dialog",
      #       dialog_id: "dialog-with-buttons"
      #     )) do |c| %>
      #       <% c.with_show_button { "Show dialog" } %>
      #       <% c.with_body do %>
      #         <p>The body of the dialog</p>
      #       <% end %>
      #       <% c.with_button { "Submit" } %>
      #       <% c.with_button { "Cancel" } %>
      #     <% end %>
      #
      # @example Dialog with form and buttons (delete category)
      #   @description
      #     If the tooltip content provides supplementary description, set `type: :description` to establish an `aria-describedby` relationship.
      #     The trigger element should also have a _concise_ accessible label via `aria-label`.
      #     Cancelling the dialog using Escape, Close or a button with `close-dialog-id` will raise the `cancel` event.
      #     Pressing a button with `submit-dialog-id` will raise the `close` event.
      #   @code
      #     <%= render(Primer::Experimental::Dialog.new(
      #       dialog_id: "delete-discussion",
      #       show_header_divider: false,
      #       show_footer_divider: false,
      #       header_variant: :large,
      #       width: :medium,
      #       title: "Delete discussion?",
      #       form_url: url_for(discussion),
      #       form_method: :delete
      #     )) do |c| %>
      #       <% c.with_show_button(scheme: :link) do |s| %>
      #         <span class="text-bold Link--primary lock-toggle-link">
      #           <%= render Primer::Beta::Octicon.new(icon: :trash, mr: 1) %> <strong>Delete discussion</strong>
      #         </span>
      #       <% end %>
      #       <% c.with_body do %>
      #         <p>The discussion will be deleted permanently. You will not be able to restore the discussion or its comments</p>
      #       <% end %>
      #       <% c.with_button(data: { "close-dialog-id": "delete-discussion" }) { "Cancel" } %>
      #       <% c.with_button(
      #         type: :submit,
      #         scheme: :danger,
      #         data: { "disable-with": "Deleting discussion…", "submit-dialog-id": "delete-discussion" }
      #       ) { "Delete discussion" } %>
      #     <% end %>
      #
      # @example Dialog with include-fragment and hover preloading set
      #   @description
      #     Set a src attribute if we wish to load an html fragment instead of rendering dialog content on page load.
      #     When preload is set to true, hovering or focusing the show_button element will cause the html fragement to load.
      #   @code
      #     <%= render(Primer::Experimental::Dialog.new(
      #       dialog_id: "dialog-with-html-fragment",
      #       title: "This is the title of the dialog",
      #       src: fragment_path,
      #       preload: true,
      #     )) do |c| %>
      #       <% c.with_show_button(**show_button_props.merge(test_selector: "my-show-button")) do |s| %>
      #           Open Dialog
      #       <% end %>
      #       <% c.with_include_fragment(test_selector: "my-dialog-fragment") do |s| %>
      #         <div data-hide-on-error>
      #           <h5>Loading...</h5>
      #           <%= render(Primer::Beta::Spinner.new(size: :small, mt: 1)) %>
      #         </div>
      #         <div data-show-on-error hidden>
      #           <h5>Sorry, something went wrong.</h5>
      #         </div>
      #       <% end %>
      #     <% end %>
      #
      # @param title [String] The title of the dialog.
      # @param description [String] The optional description of the dialog.
      # @param dialog_id [String] The optional ID of the dialog, defaults to random string.
      # @param form_url [String] The optional URL to submit the form to, form rendered when set.
      # @param form_method [Symbol] The optional form method, defaults to :post.
      # @param form_classes [String] The optional form classes, defaults to nil, format with space: "class-a class-b".
      # @param form_id [String] The optional form id, defaults to #{dialog_id}-form.
      # @param close_button_id [String] Optional id to reference a close button within the dialog. Referenced DOM element must be a valid HTML Button element.
      # @param show_header [Boolean] Whether to show the header element, if false you must provide a close button id.
      # @param show_header_divider [Boolean] Whether to show the header divider.
      # @param show_footer_divider [Boolean] Whether to show the footer divider.
      # @param width [Symbol] The width of the dialog. <%= one_of(Primer::Experimental::Dialog::WIDTH_OPTIONS) %>
      # @param height: [Symbol] The height of the dialog. <%= one_of(Primer::Experimental::Dialog::HEIGHT_OPTIONS) %>
      # @param position [Symbol] The position of the dialog. <%= one_of(Primer::Experimental::Dialog::POSITION_OPTIONS) %>
      # @param position_narrow [Symbol] The position of the dialog when narrow. <%= one_of(Primer::Experimental::Dialog::POSITION_NARROW_OPTIONS) %>
      # @param footer_content_align [Symbol] The alignment of the footer content. <%= one_of(Primer::Experimental::Dialog::FOOTER_CONTENT_ALIGN_OPTIONS) %>
      # @param header_variant [Symbol] The variant of the header. <%= one_of(Primer::Experimental::Dialog::HEADER_VARIANT_OPTIONS) %>
      # @param body_padding_variant [Symbol] The padding variant of the dialog body. <%= one_of(Primer::Experimental::Dialog::BODY_PADDING_VARIANT_OPTIONS) %>
      # @param motion [Symbol] The motion of the dialog. <%= one_of(Primer::Experimental::Dialog::MOTION_OPTIONS) %>
      # @param src [String] When present adds an `include-fragment` element to the dialog body, with the given source URL.
      # @param preload [Boolean] When true, and src is present, loads the src html fragment on show_button hover.
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      sig do
        params(
          title: String,
          description: T.nilable(String),
          dialog_id: T.nilable(String),
          form_url: T.nilable(String),
          form_method: T.nilable(Symbol),
          form_classes: T.nilable(String),
          form_id: T.nilable(String),
          close_button_id: T.nilable(String),
          show_header: T::Boolean,
          show_header_divider: T::Boolean,
          show_footer_divider: T::Boolean,
          width: Symbol,
          height: Symbol,
          position: Symbol,
          position_narrow: Symbol,
          footer_content_align: Symbol,
          header_variant: Symbol,
          body_padding_variant: Symbol,
          motion: Symbol,
          src: T.nilable(String),
          preload: T::Boolean,
          system_arguments: Primer::SystemArgumentsValue
        )
        .void
      end
      def initialize(
          title:, description: nil,
          dialog_id: "dialog-#{SecureRandom.hex(4)}",
          form_url: nil,
          form_method: :post,
          form_classes: nil,
          form_id: "#{dialog_id}-form",
          close_button_id: nil,
          show_header: true,
          show_header_divider: true,
          show_footer_divider: true,
          width: DEFAULT_WIDTH,
          height: DEFAULT_HEIGHT,
          position: DEFAULT_POSITION,
          position_narrow: DEFAULT_POSITION_NARROW,
          footer_content_align: DEFAULT_FOOTER_CONTENT_ALIGN,
          header_variant: DEFAULT_HEADER_VARIANT,
          body_padding_variant: DEFAULT_BODY_PADDING_VARIANT,
          motion: DEFAULT_MOTION,
          src: nil,
          preload: false,
          **system_arguments)
        # Set @system_arguments to an empty hash if nil to avoid passing nil to `deny_tag_argument`
        @system_arguments = T.let(deny_tag_argument(**system_arguments), T::Hash[Symbol, T.untyped])

        raise ArgumentError, "to hide the header you must provide a valid close button id" if !show_header && close_button_id.blank?

        @system_arguments[:tag] = "modal-dialog"
        @system_arguments[:role] = :dialog

        @show_header = show_header
        @close_button_id = close_button_id
        @show_header_divider = show_header_divider
        @show_footer_divider = show_footer_divider
        @width = width
        @height = height
        @position = position
        @position_narrow = position_narrow
        @footer_content_align = footer_content_align
        @header_variant = header_variant
        @body_padding_variant = body_padding_variant
        @motion = motion
        @src = src
        @preload = preload

        @form_url = form_url
        @form_method = form_method
        @form_classes = form_classes
        @form_id = form_id

        @title = title
        @description = description
        @system_arguments[:id] = dialog_id.to_s

        @header_id = T.let("#{dialog_id}-header", String)

        @backdrop_classes = T.let(class_names(
          POSITION_MAPPINGS[fetch_or_fallback(POSITION_OPTIONS, position, DEFAULT_POSITION)],
          POSITION_NARROW_MAPPINGS[fetch_or_fallback(POSITION_NARROW_MAPPINGS, position_narrow, DEFAULT_POSITION_NARROW)],
        ), String)

        @header_classes = T.let(class_names(
          HEADER_VARIANT_MAPPINGS[fetch_or_fallback(HEADER_VARIANT_OPTIONS, header_variant, DEFAULT_HEADER_VARIANT)],
          "Overlay-header--divided": show_header_divider,
        ), String)

        @body_classes = T.let(class_names(
          BODY_PADDING_VARIANT_MAPPINGS[fetch_or_fallback(BODY_PADDING_VARIANT_OPTIONS, body_padding_variant, DEFAULT_BODY_PADDING_VARIANT)]
        ), String)

        @footer_classes = T.let(class_names(
          FOOTER_CONTENT_ALIGN_MAPPINGS[fetch_or_fallback(FOOTER_CONTENT_ALIGN_OPTIONS, footer_content_align, DEFAULT_FOOTER_CONTENT_ALIGN)],
          "Overlay-footer--divided": show_footer_divider
        ), String)

        @system_arguments[:classes] = class_names(
          "Overlay",
          WIDTH_MAPPINGS[fetch_or_fallback(WIDTH_OPTIONS, width, DEFAULT_WIDTH)],
          HEIGHT_MAPPINGS[fetch_or_fallback(HEIGHT_OPTIONS, height, DEFAULT_HEIGHT)],
          MOTION_MAPPINGS[fetch_or_fallback(MOTION_OPTIONS, motion, DEFAULT_MOTION)],
          system_arguments[:classes]
        )

        if @description.present?
          @description_id = T.let("#{dialog_id}-description", String)
          @system_arguments[:aria] = { modal: true, labelledby: @header_id, describedby: @description_id }
        else
          @system_arguments[:aria] = { modal: true, labelledby: @header_id }
        end

        if @src.present? && @preload == true
          @system_arguments[:preload] = true
        end
      end

      sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def render_form(&block)
        if @form_url.present?
          form_tag @form_url, method: @form_method, class: "#{@form_classes}", id: @form_id do
            yield
          end
        else
          yield
        end
      end
    end
  end
end
