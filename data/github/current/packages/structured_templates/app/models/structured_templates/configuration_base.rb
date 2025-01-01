# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class ConfigurationBase
    include ActiveModel::Validations
    include StructuredTemplates::ValidationHelpers

    attr_reader :user_inputs, :body, :raw_data, :type_field_enabled
    attr_accessor :required_fields_enabled

    DOCS_URL = "https://docs.github.com/communities/using-templates-to-encourage-useful-issues-and-pull-requests/common-validation-errors-when-creating-issue-forms"
    SYNTAX_DOCS_URL = "https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms#about-yaml-syntax-for-issue-forms"
    FORBIDDEN_KEYS = /(y|Y|yes|Yes|YES|n|N|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF):/

    # Inputs that are contained in a structured template but do not accept
    # user input.
    NON_SUBMITTABLE_INPUTS = [StructuredTemplates::Markdown]

    # Inputs that have labels for other inputs nested under their `attributes`.
    # These classes should implement a `#nested_ids` method that returns
    # an Array of IDs (which can be generated from labels) that should be unique.
    NESTED_LABEL_INPUTS = [StructuredTemplates::Checkboxes]

    def initialize(input:, path:, type_field_enabled: false)
      @input = input
      @path = path
      @required_fields_enabled = true
      @type_field_enabled = type_field_enabled
    end

    def load
      validate_input
      return self if errors.any? # don't even parse if there is no valid input

      validate_no_forbidden_keys
      return self if errors.any? # don't even build if there are forbidden keys

      build
      return self if errors.any? # don't do domain validation if YAML isn't even parsable

      validate_types(@raw_data, required_keys, optional_keys)
      validate_no_extra_keys

      build_inputs
      return self if errors[:template].any? # don't continue validation if we have any invalid input syntax

      ensure_accepts_user_input
      validate_unique_ids_and_labels
      validate_nested_label_clashes
      self
    end

    # override AR behavior which clears out errors array
    def valid?
      errors.empty?
    end

    private

    def build
      raise NotImplementedError, "#{self.class.name} must define `#build`"
    end

    def required_keys
      raise NotImplementedError, "#{self.class.name} must define `#required_keys`"
    end

    def optional_keys
      raise NotImplementedError, "#{self.class.name} must define `#optional_keys`"
    end

    def expected_keys
      raise NotImplementedError, "#{self.class.name} must define `#expected_keys`"
    end

    def validate_input
      return unless @input.nil?
      errors.add :base, "No valid config found in path", docs: DOCS_URL
    end

    def build_inputs
      return unless has_type?(@body, "Array")

      typed_inputs = @body.compact.map.with_index do |input, index|
        if !input.is_a?(Hash)
          # add distinct error for non-hash inputs so we can stop further validation just for this case
          errors.add :template, "body[#{index}]: Invalid template syntax", docs: "#{SYNTAX_DOCS_URL}"
          next
        end
        check_input_attributes(input)
        check_input_type(index, input)
        check_input_required_fields(input)
        input_block = InputBase.create_from_input_hash(input)
        unless input_block.valid?
          input_block.errors.each { |e| errors.add :base, "body[#{index}]: #{e.message}", docs: e.options[:docs] }
        end
        input_block
      end

      @body = typed_inputs
      @user_inputs = typed_inputs.reject do |input|
        NON_SUBMITTABLE_INPUTS.include?(input.class)
      end
    end

    def check_input_type(index, input)
      if input["type"].nil?
        errors.add :base, "body[#{index}]: Required key `type` is missing", docs: "#{DOCS_URL}#bodyi-required-key-type-is-missing"
      elsif !InputBase.valid_input_type?(input["type"])
        errors.add :base, "body[#{index}]: `#{input["type"]}` is not a valid input type", docs: "#{DOCS_URL}#bodyi-x-is-not-a-valid-input-type"
      end
    end

    def check_input_attributes(input)
      if !input["attributes"].is_a?(Hash)
        # if the attributes is not a hash, we force it here to be able to run
        # the validations below and report a useful error to the user
        input["attributes"] = {}
      end
    end

    def check_input_required_fields(input)
      if !required_fields_enabled
        # disable required fields for inputs if not enabled
        if input["validations"].is_a?(Hash)
          input["validations"]["required"] = false
        end
        if input["attributes"]["options"].is_a?(Array)
          input["attributes"]["options"].map! do |option|
            option["required"] = false if option.is_a?(Hash)
            option
          end
        end
      end
    end

    def ensure_accepts_user_input
      errors.add :base, "Body cannot be empty", docs: "#{DOCS_URL}#body-cannot-be-empty-when-issue_body-is-false" if body.nil? || body.empty?
      errors.add :base, "Body must contain at least one non-markdown field", docs: "#{DOCS_URL}#body-must-contain-at-least-one-non-markdown-field" if no_user_inputs?
    end

    def validate_unique_ids_and_labels
      return unless has_type?(@body, "Array")
      label_clashes = user_input_elements.group_by { |e| e.label }.select { |_, elems| elems.length > 1 }
      id_clashes = user_input_elements.group_by { |e| e.id }.select { |_, elems| elems.length > 1 }

      if label_clashes.any?
        # if clashing labels not differentiated by unique IDs, let's activate the tripwire and bail
        also_clashing_ids = T.let(false, T::Boolean)
        label_clashes.each do |_, elements|
          if (also_clashing_ids = elements.uniq(&:id) != elements)
            if elements.map(&:auto_id).all?(false) # if these are all user-supplied ids
              errors.add :base, "Body must have unique `id`s", docs: "#{DOCS_URL}#body-must-have-unique-ids"
            else # else, we generated the ids
              errors.add :base, "Body must have unique `label`s", docs: "#{DOCS_URL}#body-must-have-unique-labels"
            end
          end
        end
        return if also_clashing_ids
      end

      if id_clashes.any?
        # are the IDs clashing because of user input error?
        user_supplied_ids = id_clashes.map { |_, inputs| inputs.map(&:auto_id).any?(false) } # auto_id=false means user defined it
        return errors.add :base, "Body must have unique `id`s", docs: "#{DOCS_URL}#body-must-have-unique-ids" if user_supplied_ids.any?

        # otherwise, mea culpa - they didn't know their labels would become IDs
        errors.add :base, "Labels are too similar", docs: "#{DOCS_URL}#labels-are-too-similar"
      end
    end

    def validate_nested_label_clashes
      return unless has_type?(@body, "Array")
      nested_inputs = user_input_elements.select { |i| NESTED_LABEL_INPUTS.include?(i.class) }
      return if nested_inputs.empty?

      all_identifiers = nested_inputs.flat_map(&:nested_ids).uniq + user_input_elements.map(&:id)
      if all_identifiers.uniq != all_identifiers
        errors.add :base, "Checkboxes must have unique `label`s", docs: "#{DOCS_URL}#checkboxes-must-have-unique-labels"
      end
    end

    def user_input_elements
      return @user_input_elements if defined?(@user_input_elements)
      @user_input_elements = @body.select { |i| InputBase.user_input_type?(i.type) }
    end

    def no_user_inputs?
      return if @body.nil? || !has_type?(@body, "Array")
      body.select(&:valid?).flat_map(&:type).uniq == ["markdown"]
    end

    def validate_no_extra_keys
      all_keys = @raw_data.keys.map(&:to_sym)
      extra_keys = all_keys - expected_keys

      if extra_keys.any?
        extra_keys.each { |k| self.errors.add :base, "`#{k}` is not a permitted key", docs: "#{DOCS_URL}#input-is-not-a-permitted-key" }
      end
    end

    def validate_no_forbidden_keys
      if @input.split("\n").any? { |line| line.starts_with?(FORBIDDEN_KEYS) }
        errors.add(
          :base,
          "Config contains reserved YAML keywords as keys",
          docs: "#{DOCS_URL}#input-is-not-a-permitted-key",
        )
      end
    end
  end
end
