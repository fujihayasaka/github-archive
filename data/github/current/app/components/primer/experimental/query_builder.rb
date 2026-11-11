# typed: strict
# frozen_string_literal: true

# Note: This has not been used in production yet - please reach out to @github/accessibility
# if you are interested in using this component so we can assist with implementation!

module Primer
  module Experimental
    # The QueryBuilder should be used when a user wants to enter a query that will narrow results or complete a search.
    #
    # Using an event system, the QueryBuilder emits an event whenever the input value changes. Providers (defined by the consumer of the component) will determine what to do with the new query when the events are emitted. They will then send back new results (if desired) to the QueryBuilder.
    #
    # There are three types of items that can be displayed (see the full API for more info ui/packages/query-builder-element/query-builder-api.ts):
    # 1. Filter - represents a parametric qualifier that can be used to refine the scope of a search. (i.e. `repo:` or `author:`)
    # 2. FilterItem - represents a value that can be used in a filter. (i.e. `repo:accessibility` where `repo:` is the filter and `accessibility` is the filter value)`
    # 3. SearchItem - represents a result that appears in the results list, and has an action for a user to enact on
    class QueryBuilder < Primer::Component
      FILTER_KEY_DEFAULT = ":"
      FILTER_KEY_OPTIONS = T.let([FILTER_KEY_DEFAULT, ">"], T::Array[String])
      DEFAULT_SIZE = :medium
      SIZE_MAPPINGS = T.let({
        :small => "FormControl-small",
        DEFAULT_SIZE => "FormControl-medium",
        :large => "FormControl-large"
      }.freeze, T::Hash[Symbol, String])
      SIZE_OPTIONS = T.let(SIZE_MAPPINGS.keys, T::Array[Symbol])

      # Leading visual.
      #
      # - `leading_visual_icon` for a <%= link_to_component(Primer::Beta::Octicon) %>.
      #
      # @param system_arguments [Hash] Same arguments as <%= link_to_component(Primer::Beta::Octicon) %>.
      renders_one :leading_visual, types: {
        icon: lambda { |**system_arguments|
          T.bind(self, Primer::Experimental::QueryBuilder)
          system_arguments[:classes] = class_names("FormControl-input-leadingVisual")
          Primer::Beta::Octicon.new(**system_arguments)
        }
      }

      # Customizable input used to search for results.
      # It is preferred to use this slot sparingly - it will be created by default if not explicity added.
      #
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      renders_one :input, lambda { |**system_arguments|
        T.bind(self, Primer::Experimental::QueryBuilder)
        sanitized_args = deny_tag_argument(**system_arguments)
        sanitized_args = deny_single_argument(:autofocus, "autofocus is not allowed for accessibility reasons. See https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/autofocus#accessibility_considerations for more information.", **sanitized_args)
        deny_aria_key(
          :label,
          "instead of `aria-label`, include `label_text`.",
          **sanitized_args
        )
        deny_single_argument(
          :id,
          "`id` will always be set to @id.",
          **sanitized_args
        )
        deny_single_argument(
          :name,
          "Set @input_name on the component initializer instead with `input_name`.",
          **sanitized_args
        )
        deny_single_argument(
          :invalid,
          "Set @invalid on the component initializer instead with `invalid`.",
          **sanitized_args
        )
        deny_single_argument(
          :required,
          "Set @required on the component initializer instead with `required`.",
          **sanitized_args
        )
        @id = T.let(@id, T.nilable(String))
        @invalid = T.let(@invalid, T.nilable(T::Boolean))
        @required = T.let(@required, T.nilable(T::Boolean))
        sanitized_args[:id] = @id
        @input_name = T.let(@input_name, T.nilable(String))
        sanitized_args[:name] = @input_name
        sanitized_args[:tag] = :input
        @value = T.let(@value, T.nilable(String))
        sanitized_args[:value] = @value
        sanitized_args[:autocomplete] = "off"
        sanitized_args[:type] = :text
        sanitized_args[:role] = "combobox"
        @size = T.let(@size, T.nilable(Symbol))
        sanitized_args[:classes] = class_names(
          "FormControl-input",
          "QueryBuilder-Input",
          SIZE_MAPPINGS[fetch_or_fallback(SIZE_OPTIONS, @size, DEFAULT_SIZE)],
          sanitized_args[:classes],
        )
        @placeholder = T.let(@placeholder, T.nilable(String))
        sanitized_args[:placeholder] = @placeholder
        sanitized_args[:spellcheck] = false
        sanitized_args[:invalid] = @invalid if @invalid
        sanitized_args[:aria] = (sanitized_args[:aria] || {}).merge({
          "expanded": false,
          "describedby": validation_id,
          "invalid": @invalid ? "true" : nil,
          "required": @required ? "true" : nil,
        })
        sanitized_args[:data] = (sanitized_args[:data] || {}).merge({ "target": "query-builder.input" })
        sanitized_args[:data] = (sanitized_args[:data] || {}).merge({ "action": "
          input:query-builder#inputChange
          blur:query-builder#inputBlur
          keydown:query-builder#inputKeydown
          focus:query-builder#inputFocus
        " })
        Primer::BaseComponent.new(**sanitized_args)
      }

      # @param invalid [Boolean] If set to true, the input will be rendered with a red border.
      # @param validation_message [String] A string displayed after the input indicating the input's contents are invalid.
      # @param required  [Boolean] Default false. When set to true, causes an asterisk (*) to appear next to the field's label indicating it is a required field. Note that this option explicitly does not add a required HTML attribute. Doing so would enable native browser validations, which are inaccessible and inconsistent with the Primer design system.
      # @param visually_hide_label [Boolean] Controls if the label is visible. If `true`, screen reader only text will be added.
      sig do
        params(
          id: String,
          label_text: String,
          form_action_url: String,
          filter_key: String,
          input_name: T.nilable(String),
          placeholder: T.nilable(String),
          invalid: T::Boolean,
          validation_message: T.nilable(String),
          required: T::Boolean,
          visually_hide_label: T::Boolean,
          size: Symbol,
          clear_button_system_arguments: T::Hash[String, String],
          show_clear_button: T::Boolean,
          persist_list: T::Boolean,
          use_overlay: T::Boolean,
          value: String,
          form_wrap: T::Boolean,
          hidden_form_fields: T::Hash[T.any(String, Symbol), T.untyped],
          system_arguments: Primer::SystemArgumentsValue
        )
        .void
      end
      def initialize(id:, label_text:, form_action_url:, filter_key: FILTER_KEY_DEFAULT, input_name: nil, placeholder: nil, invalid: false, validation_message: nil, required: false, visually_hide_label: false, size: DEFAULT_SIZE, clear_button_system_arguments: {}, show_clear_button: true, persist_list: false, use_overlay: true, value: "", form_wrap: true, hidden_form_fields: {}, **system_arguments)
        @id = id
        @label_text = label_text
        @form_action_url = form_action_url
        @placeholder = placeholder
        @validation_message = validation_message
        @invalid = T.let(invalid || !validation_message.nil?, T::Boolean)
        @required = required
        @visually_hide_label = visually_hide_label
        @input_name = T.let(input_name || @id, T.nilable(String))
        @size = size
        @clear_button_system_arguments = clear_button_system_arguments
        @value = value
        @system_arguments = T.let(deny_tag_argument(**system_arguments), T::Hash[Symbol, T.untyped])
        @system_arguments[:tag] = :"query-builder"
        @system_arguments[:id] = :"query-builder-#{@id}"
        @system_arguments[:classes] = class_names(
          "QueryBuilder",
          system_arguments[:classes]
        )
        @system_arguments[:"data-filter-key"] = fetch_or_fallback(FILTER_KEY_OPTIONS, filter_key, FILTER_KEY_DEFAULT).to_s
        @show_clear_button = show_clear_button
        @persist_list = persist_list
        @use_overlay = use_overlay
        @form_wrap = form_wrap
        @hidden_form_fields = hidden_form_fields
      end

      sig { returns(T::Boolean) }
      def form_wrap?
        @form_wrap
      end

      # add `input` without needing to explicitly call it in the view
      sig { returns(T.nilable(ViewComponent::Slot)) }
      def before_render
        with_input(classes: "") unless input?
      end

      private

      sig { params(args: T.untyped, kwargs: T.untyped, block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def conditional_form_tag(*args, **kwargs, &block)
        if form_wrap?
          T.unsafe(self).form_tag(*args, **kwargs, &block)
        else
          capture { block.call }
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def validation_arguments
        {
          class: "FormControl-inlineValidation",
          id: validation_id,
          hidden: @validation_message.nil?
        }
      end

      sig { returns(String) }
      def validation_id
        @validation_id ||= T.let("validation-#{SecureRandom.uuid}", T.nilable(String))
      end
    end
  end
end
