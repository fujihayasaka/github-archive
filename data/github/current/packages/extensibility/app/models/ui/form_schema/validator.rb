# typed: true
# frozen_string_literal: true

module UI
  class FormSchema
    class Validator < UI::Validator
      MAX_FIELDS_LIMIT = 25
      MAX_OPTIONS_LIMIT = 100

      VALID_TYPES = %w[
        input
        textarea
        dropdown
        checkboxes
        markdown
      ]
      GENERAL_EXPECTED_KEYS = %w(
        attributes
        type
      )
      GENERAL_OTHER_KEYS = %w(
        validations
      )

      EXPECTED_KEYS = {
        "input" => GENERAL_EXPECTED_KEYS,
        "textarea" => GENERAL_EXPECTED_KEYS,
        "dropdown" => GENERAL_EXPECTED_KEYS,
        "checkboxes" => GENERAL_EXPECTED_KEYS,
        "markdown" => GENERAL_EXPECTED_KEYS,
      }
      OTHER_KEYS = {
        "input" => GENERAL_OTHER_KEYS,
        "textarea" => GENERAL_OTHER_KEYS,
        "dropdown" => GENERAL_OTHER_KEYS,
        "checkboxes" => GENERAL_OTHER_KEYS,
      }

      ALLOWED_INPUT_ATTRIBUTE_KEYS = %w[
        label
        id
        description
        placeholder
        value
        format
      ]
      ALLOWED_INPUT_VALIDATION_KEYS = %w(
        required
        minLength
        maxLength
        format
      )

      ALLOWED_TEXTAREA_ATTRIBUTE_KEYS = %w[
        label
        id
        description
        placeholder
        value
      ]
      ALLOWED_TEXTAREA_VALIDATION_KEYS = %w(
        required
      )

      ALLOWED_DROPDOWN_ATTRIBUTE_KEYS = %w[
        label
        id
        description
        placeholder
        value
        multiple
        options
      ]
      ALLOWED_DROPDOWN_VALIDATION_KEYS = %w(
        required
      )

      ALLOWED_CHECKBOXES_ATTRIBUTE_KEYS = %w[
        label
        id
        description
        value
        options
      ]
      ALLOWED_CHECKBOXES_VALIDATION_KEYS = %w(
        required
      )

      ALLOWED_OPTION_KEYS = %w[
        label
        value
        required
      ]

      attr_reader :base_key

      def initialize(schema, base_key: nil)
        super(schema)
        @base_key = base_key
      end

      def validate!
        # We must have an array, or we can't even start parsing
        unless schema.is_a?(Array)
          errors.add(
            backtick(base_key) || :base,
            "was expected to an `Array` but was a #{backtick(schema.class.name)}"
          )
          return
        end

        validate_max_size(
          target: base_key || :base,
          size: schema.size,
          limit: MAX_FIELDS_LIMIT,
          label: "field",
        )

        labels = {}
        schema.each_with_index do |element, idx|
          key = "#{base_key}[#{idx}]"

          # Each element should be a hash, otherwise we can't do anything
          unless element.is_a?(Hash)
            errors.add(backtick(key), "was expected to be a `Hash` but was a #{backtick(element.class.name)}")
            next
          end

          element = element.deep_stringify_keys

          unless element["type"].is_a?(String)
            errors.add(
              backtick("#{key}.type"),
              "was expected to be a `String` but it was a #{backtick(element["type"].class.name)}"
            )
            next
          end

          expected_element_keys = EXPECTED_KEYS[element["type"]] || []
          optional_element_keys = OTHER_KEYS[element["type"]] || []

          next unless validate_expected_keys(key, expected_element_keys, element.keys, optional: optional_element_keys)

          if expected_element_keys.include?("attributes") && !validate_type(key, "#{key}.attributes", element["attributes"], Hash)
            next
          end

          # Record the index for a given label. Helps us ensure unique labels
          if element["attributes"].is_a?(Hash)
            labels[element.dig("attributes", "label")] ||= []
            labels[element.dig("attributes", "label")] << idx
          end

          # Next validate each specific type
          case element["type"]
          when "input"      then validate_input(key, element)
          when "textarea"   then validate_textarea(key, element)
          when "dropdown"   then validate_dropdown(key, element)
          when "checkboxes" then validate_checkboxes(key, element)
          when "markdown"   then validate_markdown(key, element)
          when nil then errors.add(backtick("#{key}.type"), "must be provided")
          else errors.add(backtick("#{key}.type"), "is not a valid type: #{backtick(element["type"])}")
          end
        end

        # Indicate errors on any duplicate labels
        labels.each do |label, idxs|
          next if label.nil? || idxs.size < 2
          idxs.each do |idx|
            errors.add(backtick("#{base_key}[#{idx}].label"), "was not unique")
          end
        end
      end

      private

      def validate_input(key, element)
        attribute_key = "#{key}.attributes"
        attributes = element["attributes"]

        # Validate attribute options are valid
        validate_inclusion(
          key: key,
          label: ".attributes",
          values: attributes.keys,
          allowed_values: valid_attribute_options_for("input"),
        )

        validate_label_attribute(attribute_key, attributes)

        # Validate various attributes are strings if they exist
        %w( description placeholder value ).each do |attr|
          next if attributes[attr].blank? || attributes[attr].is_a?(String)
          errors.add(backtick("#{attribute_key}.#{attr}"), "was expected to be a `String`")
        end

        # Validate textType is one of the enum values if it exists
        types = %w(text phone number date email)
        if attributes["format"] && !types.include?(attributes["format"])
          types_scentence = types
            .map { |type| backtick(type) }
            .to_sentence(last_word_connector: ", or ")
          errors.add(backtick("#{attribute_key}.format"), "was expected to be one of #{types_scentence}")
        end

        # Finally, ensure validations are as expected
        validate_validations(key, element, [:required, :minLength, :maxLength])
      end

      def validate_textarea(key, element)
        attribute_key = "#{key}.attributes"
        attributes = element["attributes"]

        # Validate attribute options are valid
        validate_inclusion(
          key: key,
          label: ".attributes",
          values: attributes.keys,
          allowed_values: valid_attribute_options_for("textarea"),
        )

        validate_label_attribute(attribute_key, attributes)

        # Validate various attributes are strings if they exist
        %w( description placeholder value ).each do |attr|
          next if attributes[attr].blank? || attributes[attr].is_a?(String)
          errors.add(
            backtick("#{attribute_key}.#{attr}"),
            "was expected to be a `String` but it was a #{backtick(attributes[attr].class.name)}"
          )
        end

        # Finally, ensure validations are as expected
        validate_validations(key, element, [:required, :minLength, :maxLength])
      end

      def validate_dropdown(key, element)
        attribute_key = "#{key}.attributes"
        attributes = element["attributes"]

        # Validate attribute options are valid
        validate_inclusion(
          key: key,
          label: ".attributes",
          values: attributes.keys,
          allowed_values: valid_attribute_options_for(element["type"]),
        )

        validate_label_attribute(attribute_key, attributes)

        # Validate options exists and is a string
        if attributes["options"] && !attributes["options"].is_a?(Array)
          errors.add(
            backtick("#{attribute_key}.options"),
            "was expected to be an `Array` but it was a #{backtick(attributes["options"].class.name)}"
          )
        elsif attributes["options"].blank?
          errors.add(backtick(attribute_key), "was expected to have the key `options`")
        end
        validate_options("#{attribute_key}.options", attributes["options"])

        # Validate various attributes are strings if they exist
        %w( description placeholder ).each do |attr|
          next if attributes[attr].blank? || attributes[attr].is_a?(String)
          errors.add(
            backtick("#{attribute_key}.#{attr}"),
            "was expected to be a `String` but it was a #{backtick(attributes[attr].class.name)}"
          )
        end

        if attributes["value"] && !(attributes["value"].is_a?(String) || attributes["value"].is_a?(Array))
          errors.add(
            backtick("#{attribute_key}.value"),
            "was expected to be a `String` or an `Array` but it was a #{backtick(attributes["value"].class.name)}"
          )
        end

        # Finally, ensure validations are as expected
        validate_validations(key, element, [:required])
      end

      def validate_checkboxes(key, element)
        attribute_key = "#{key}.attributes"
        attributes = element["attributes"]

        # Validate attribute options are valid
        validate_inclusion(
          key: key,
          label: ".attributes",
          values: attributes.keys,
          allowed_values: valid_attribute_options_for(element["type"]),
        )

        validate_label_attribute(attribute_key, attributes)

        # Validate options exists and is a string
        if attributes["options"] && !attributes["options"].is_a?(Array)
          errors.add(
            backtick("#{attribute_key}.options"),
            "was expected to be an `Array` but it was a #{backtick(attributes["options"].class.name)}"
          )
        elsif attributes["options"].blank?
          errors.add(backtick(attribute_key), "was expected to have the key `options`")
        end
        validate_options("#{attribute_key}.options", attributes["options"])

        # Validate various attributes are strings if they exist
        %w( description placeholder ).each do |attr|
          next if attributes[attr].blank? || attributes[attr].is_a?(String)
          errors.add(
            backtick("#{attribute_key}.#{attr}"),
            "was expected to be a `String` but it was a #{backtick(attributes[attr].class.name)}"
          )
        end

        if attributes["value"] && !(attributes["value"].is_a?(String) || attributes["value"].is_a?(Array))
          errors.add(
            backtick("#{attribute_key}.value"),
            "was expected to be a `String` or an `Array` but it was a #{backtick(attributes["value"].class.name)}"
          )
        end

        # Finally, ensure validations are as expected
        validate_validations(key, element, [:required])
      end

      def validate_options(key, options)
        return unless options && options.is_a?(Array)

        validate_max_size(
          target: "#{key}",
          size: options.size,
          limit: MAX_OPTIONS_LIMIT,
          label: "option",
        )

        options.each_with_index do |option, index|
          unless option.is_a?(Hash)
            errors.add(backtick("#{key}[#{index}]"), "was expected to be a `Hash` but was a #{backtick(option.class.name)}")
            next
          end

          validate_inclusion(
            key: key,
            label: "[#{index}]",
            values: option.keys,
            allowed_values: ALLOWED_OPTION_KEYS,
          )

          validate_label_attribute("#{key}[#{index}]", option)
        end
      end

      def validate_markdown(key, element)
        attribute_key = "#{key}.attributes"
        attributes = element["attributes"]
        expected = %w( value )

        expected.each do |expected_attr|
          if attributes[expected_attr].blank?
            errors.add(
              backtick("#{attribute_key}"),
              "was expected to have the key #{backtick(expected_attr)}"
            )
          elsif !attributes[expected_attr].is_a?(String)
            errors.add(
              backtick("#{attribute_key}.#{expected_attr}"),
              "was expected to be a `String` but it was a #{backtick(attributes[expected_attr].class.name)}"
            )
          end
        end
      end

      def validate_validations(key, element, validations)
        return if element["validations"].blank?

        unless element["validations"].is_a?(Hash)
          errors.add(
            backtick("#{key}.validations"),
            "was expected to be a `Hash` but it was a #{backtick(element["validations"].class.name)}"
          )
          return
        end

        # Validate validation options are valid
        validate_inclusion(
          key: key,
          label: ".validations",
          values: element["validations"]&.keys,
          allowed_values: valid_validation_options_for(element["type"]),
        )

        validations.each do |validation|
          case validation
          when :required
            next if element["validations"][validation.to_s].blank?
            next if element["validations"][validation.to_s].is_a?(TrueClass) || element["validations"][validation.to_s].is_a?(FalseClass)
            errors.add(
              backtick("#{key}.validations.#{validation}"),
              "was expected to be a `Boolean` but it was a #{backtick(element["validations"][validation.to_s].class.name)}"
            )
          when :minLength, :maxLength
            next if element["validations"][validation.to_s].blank?
            next if element["validations"][validation.to_s].is_a?(Integer)
            errors.add(
              backtick("#{key}.validations.#{validation}"),
              "was expected to be a `Integer` but it was a #{backtick(element["validations"][validation.to_s].class.name)}"
            )
          end
        end
      end

      def validate_label_attribute(attribute_key, attributes)
        # Validate name or label exists and is a string
        label, key = case
        when attributes["name"].present?
          [attributes["name"], "name"]
        when attributes["label"].present?
          [attributes["label"], "label"]
        else
          errors.add(backtick(attribute_key), "was expected to have the key `label`")
          [nil, "label"]
        end

        if label.present? && !label.is_a?(String)
          errors.add(
            backtick("#{attribute_key}.#{key}"),
            "was expected to be a `String` but it was a #{backtick(label.class.name)}"
          )
        end
      end

      def valid_attribute_options_for(element_type)
        {
          "input" => ALLOWED_INPUT_ATTRIBUTE_KEYS,
          "textarea" => ALLOWED_TEXTAREA_ATTRIBUTE_KEYS,
          "dropdown" => ALLOWED_DROPDOWN_ATTRIBUTE_KEYS,
          "checkboxes" => ALLOWED_CHECKBOXES_ATTRIBUTE_KEYS,
        }.fetch(element_type)
      end

      def valid_validation_options_for(element_type)
        {
          "input" => ALLOWED_INPUT_VALIDATION_KEYS,
          "textarea" => ALLOWED_TEXTAREA_VALIDATION_KEYS,
          "dropdown" => ALLOWED_DROPDOWN_VALIDATION_KEYS,
          "checkboxes" => ALLOWED_CHECKBOXES_VALIDATION_KEYS,
        }.fetch(element_type)
      end
    end
  end
end
