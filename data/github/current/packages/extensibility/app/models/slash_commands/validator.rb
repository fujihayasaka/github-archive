# typed: true
# frozen_string_literal: true

module SlashCommands
  class Validator < UI::Validator
    MAX_STEPS_LENGTH = 25
    MAX_TEMPLATE_LENGTH = 1024
    DEFAULT_MAX_STRING_LENGTH = 128

    VALID_TOP_LEVEL_KEYS = %w(
      trigger
      title
      description
      steps
    )
    OPTIONAL_TOP_LEVEL_KEYS = %w(surfaces)

    VALID_STRING_LENGTHS = {
      "trigger" => 40,
      "title" => 80,
      "description" => 256,
    }

    EXPECTED_FORM_KEYS = %w(type style body)
    EXPECTED_MENU_KEYS = %w(type id options)
    OPTIONAL_MENU_KEYS = %w(label)

    def validate!
      # We must have a hash, or we can't even start parsing
      unless schema.is_a?(Hash)
        errors.add(:base, "Expected schema to be an hash of elements, but was #{backtick(schema.class.name)}")
        return
      end

      @schema = @schema.stringify_keys

      return unless validate_expected_keys(:schema, VALID_TOP_LEVEL_KEYS, schema.keys, optional: OPTIONAL_TOP_LEVEL_KEYS)

      # Validate the string values are as expected
      VALID_STRING_LENGTHS.each do |key, length|
        validate_string_of_length(val: schema[key], path: key, length: length)
      end

      # Validate that surfaces is an array of supported slash command surfaces
      if schema.key?("surfaces")
        if schema["surfaces"].is_a?(Array)
          validate_inclusion(
            key: "surfaces",
            label: "",
            values: schema["surfaces"],
            allowed_values: ::SlashCommands::SUPPORTED_SURFACES.map(&:to_s),
          )
        else
          errors.add(backtick("surfaces"), "was expected to be an `Array` but was a #{backtick(schema["surfaces"].class.name)}")
        end
      end

      # Now we can validate the actual steps
      steps = schema["steps"]
      if !steps.is_a?(Array)
        errors.add(backtick("steps"), "was expected to be an `Array` but was a #{backtick(steps.class.name)}")
        return
      end

      validate_max_size(
        target: "steps",
        label: "",
        size: steps.size,
        limit: MAX_STEPS_LENGTH,
      )

      names = {}
      steps.each_with_index do |step, idx|
        key = "steps[#{idx}]"

        # Each step should be a hash, otherwise we can't do anything
        unless step.is_a?(Hash)
          errors.add(backtick(key), "was expected to be a hash, but was #{backtick(step.class.name)}")
          next
        end

        step = step.deep_stringify_keys

        # Record the index for a given name. Helps us ensure unique names
        if name = step["id"]
          names[name] ||= []
          names[name] << idx
        end

        # Next validate each specific type
        case step["type"]
        when "fill"                then validate_fill(key, step)
        when "form"                then validate_form(key, step)
        when "menu"                then validate_menu(key, step)
        when "repository_dispatch" then validate_repository_dispatch(key, step)
        else errors.add(backtick("#{key}.type"), "is not a valid type: #{backtick(step["type"])}")
        end
      end

      # Indicate errors on any duplicate names
      names.each do |name, idxs|
        next if name.nil? || idxs.size < 2
        idxs.each do |idx|
          errors.add(backtick("steps[#{idx}].id"), "was not unique")
        end
      end
    end

    private

    def validate_fill(key, step)
      if step["template"].blank? && step["template_path"].blank?
        errors.add(backtick(key), "must have `template` or `template_path` key defined")
        return
      end

      if step["template"].present? && step["template_path"].present?
        errors.add(backtick(key), "cannot define both `template` and `template_path` keys defined")
        return
      end

      if template = step["template"]
        validate_string_of_length(val: template, path: "#{key}.template", length: MAX_TEMPLATE_LENGTH)
      end

      if template_path = step["template_path"]
        validate_string_of_length(val: template_path, path: "#{key}.template_path", length: MAX_TEMPLATE_LENGTH)
      end

      if step.key?("submit_form") && !step["submit_form"].is_a?(TrueClass) && !step["submit_form"].is_a?(FalseClass)
        errors.add(backtick("#{key}.submit_form"), "was expected to be a `Boolean` but was #{backtick(step["submit_form"].class.name)}")
        nil
      end
    end

    def validate_repository_dispatch(key, step)
      if step["eventType"].blank?
        errors.add(backtick(key), "must have `eventType` key defined")
      elsif !step["eventType"].is_a?(String)
        errors.add(backtick("#{key}.eventType"), "was expected to be a `String` but was #{backtick(step["eventType"].class.name)}")
      end

      if step["repository"].present? && !step["repository"].is_a?(String)
        errors.add(backtick("#{key}.repository"), "was expected to be a `String` but was #{backtick(step["repository"].class.name)}")
      elsif step["repository"].present? && !Repository::NAME_WITH_OWNER_PATTERN.match?(step["repository"])
        errors.add(backtick("#{key}.repository"), "was expected to be in the form `<repository owner login>/<repository name>`")
      end
    end

    def validate_form(key, step)
      return unless validate_expected_keys(key, EXPECTED_FORM_KEYS, step.keys, optional: ["actions"])

      if !step["style"].is_a?(String)
        errors.add(backtick("#{key}.style"), "was expected to be a `String` but was #{backtick(step["style"].class.name)}")
      else
        validate_inclusion(
          key: key,
          label: ".style",
          values: [step["style"]],
          allowed_values: ::SlashCommands::Page::FORM_STYLES.map(&:to_s),
        )
      end

      if step["actions"].present?
        validate_form_actions("#{key}.actions", step["actions"])
      end

      validator = UI::FormSchema::Validator.new(step["body"], base_key: "#{key}.body")
      validator.validate!
      validator.errors.messages.each do |form_key, form_errors|
        form_errors.each do |error|
          errors.add(form_key, error)
        end
      end
      validator.deprecation_warnings.messages.each do |form_key, warnings|
        warnings.each do |warning|
          deprecation_warnings.add(form_key, warning)
        end
      end
    end

    def validate_form_actions(key, actions)
      unless actions.is_a?(Hash)
        errors.add(backtick(key), "was expected to be a `Hash` but was #{backtick(actions.class.name)}")
        return
      end

      if actions["submit"].present? && !actions["submit"].is_a?(String)
        errors.add(backtick("#{key}.submit"), "was expected to be a `String` but was #{backtick(actions["submit"].class.name)}")
      end
      if actions["cancel"].present? && !actions["cancel"].is_a?(String)
        errors.add(backtick("#{key}.cancel"), "was expected to be a `String` but was #{backtick(actions["cancel"].class.name)}")
      end
    end

    def validate_menu(key, step)
      return unless validate_expected_keys(key, EXPECTED_MENU_KEYS, step.keys, optional: OPTIONAL_MENU_KEYS)
      validate_string_of_length(val: step["id"], path: "#{key}.id", length: DEFAULT_MAX_STRING_LENGTH)

      if !step["options"].is_a?(Array)
        errors.add(backtick("#{key}.options"), "was expected to be an `Array` but was a #{backtick(step["options"].class.name)}")
      else
        step["options"].each_with_index do |item, idx|
          validate_string_of_length(val: item, path: "#{key}.options[#{idx}]", length: DEFAULT_MAX_STRING_LENGTH)
        end
      end
    end
  end
end
