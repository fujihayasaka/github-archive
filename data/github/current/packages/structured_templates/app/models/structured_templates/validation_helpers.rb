# typed: true
# frozen_string_literal: true

module StructuredTemplates
  module ValidationHelpers
    extend ActiveSupport::Concern
    include ActiveModel::Validations

    FORBIDDEN_LABELS = [
      "password",
      "pass word",
      "passphrase",
      "credit card",
      "creditcard",
      "ss#",
      "ssn",
      "social security number",
      "routing number",
      "bank account number"
    ]

    def validate_types(data, required_keys, optional_keys)
      required_keys.each do |key|
        if data.has_key?(key[:id])
          errors.add(
            :base,
            type_error_message(key[:id], key[:type]),
            docs: "#{ConfigurationBase::DOCS_URL}#key-must-be-a-string") unless has_type?(data[key[:id]], key[:type])
        else
          errors.add :base, "Required top-level key `#{key[:id]}` is missing", docs: "#{ConfigurationBase::DOCS_URL}#required-top-level-key-name-is-missing"
        end
      end

      optional_keys.each do |key|
        next if %w[description about].include? key[:id]
        if data.has_key?(key[:id])
          user_input = data[key[:id]]

          if key[:type].is_a? Array
            valid_type = has_types?(user_input, key[:type])
            error_msg = "`#{key[:id]}` must be of type #{key[:type].join(" or ")}"
          else
            valid_type = has_type?(user_input, key[:type])
            error_msg = type_error_message(key[:id], key[:type])
          end

          unless valid_type
            errors.add :base, error_msg, docs: "#{ConfigurationBase::DOCS_URL}#key-must-be-a-string"
          end
        end
      end
    end

    def type_error_message(key, expected_type)
      msg = "`#{key}` must be of type #{expected_type}"
      msg += " and cannot be empty" if expected_type == "String"
      msg
    end

    def validate_id(id)
      return if id.nil?

      if has_type?(id, "String")
        enforce_alphanumeric(id)
      else
        errors.add :base, type_error_message("id", "String"), docs: "#{ConfigurationBase::DOCS_URL}#bodyi-label-must-be-a-string"
      end
    end

    def enforce_alphanumeric(id)
      if id.gsub(/[^a-zA-Z0-9_-]/, "_") != id
        errors.add :base, "`id` can contain only numbers, letters, -, _", docs: "#{ConfigurationBase::DOCS_URL}#bodyi-id-can-only-contain-numbers-letters---_"
      end
    end

    # constructs the element's ID when it's not user-supplied. auto_id is set to false when user-supplied; true if we generate.
    def build_id(input, label)
      supplied_id = input.dig("id")
      return [supplied_id, false] unless supplied_id.nil?
      id = Digest::SHA256.hexdigest(label) if (T.unsafe(self).id.nil? || T.unsafe(self).id.empty?) && label.is_a?(String)
      [id, true]
    end

    def true_if_undefined(data, *keys)
      result = data.dig(*keys)
      result.nil? ? true : result
    end

    def false_if_undefined(data, *keys)
      return false unless data.is_a?(Hash)

      result = T.unsafe(data).dig(*keys)
      result.nil? ? false : result
    rescue TypeError
      false
    end

    def has_type?(input, type_string)
      if type_string == "Boolean"
        return [true, false].include?(input)
      elsif type_string == "String"
        return false if input.blank?
      end

      input&.class&.name == type_string
    end

    def has_types?(input, types)
      types.any? { |type| has_type?(input, type) }
    end

    def no_extra_keys
      return unless T.unsafe(self).input&.keys&.any?

      all_keys = T.unsafe(self).input.keys.map(&:to_sym)
      expected_keys = [:type, :attributes, :validations, :id]
      extra_keys = all_keys - expected_keys

      if extra_keys.any?
        extra_keys.each { |k| self.errors.add :base, "`#{k}` is not a permitted key", docs: "#{ConfigurationBase::DOCS_URL}#bodyi-x-is-not-a-permitted-key" }
      end
    end

    def check_extraneous_attributes(expected, actual)
      return if actual.blank?

      all_attrs = actual.map(&:to_sym)
      expected_attrs = expected.pluck(:id)
      extra_attrs = all_attrs - expected_attrs

      if extra_attrs.any?
        extra_attrs.each do |attr|
          self.errors.add :base, "`#{attr}` is not a permitted attribute",
            docs: "#{ConfigurationBase::DOCS_URL}#bodyi-x-is-not-a-permitted-attribute"
        end
      end
    end

    def no_forbidden_label
      return if T.unsafe(self).label.nil? || !has_type?(T.unsafe(self).label, "String")

      contains_forbidden_word = FORBIDDEN_LABELS.any? { |word| T.unsafe(self).label.downcase.include? word }

      self.errors.add :base, "Label contains a forbidden word", docs: "#{ConfigurationBase::DOCS_URL}#bodyi-label-contains-forbidden-word" if contains_forbidden_word
    end

    def valid_options
      # another validation takes care of type checking. This ensures that we only return a unique/none error when the
      # input is properly formatted, and the error is truly one of not being unique/using none.
      return unless T.unsafe(self).options.is_a?(Array)

      if T.unsafe(self).options.length != T.unsafe(self).options.map { |choice| choice.is_a?(String) ? choice.downcase : choice }.uniq.length
        self.errors.add(:base, "`options` must be unique", docs: "#{ConfigurationBase::DOCS_URL}#bodyi-options-must-be-unique")
      end

      if T.unsafe(self).options.map { |choice| choice.is_a?(String) ? choice.downcase : choice }.include?("none")
        self.errors.add(:base, "`options` must not include the reserved word, 'None'",
                        docs: "#{ConfigurationBase::DOCS_URL}#bodyi-options-must-not-include-the-reserved-word-none")
      end

      if T.unsafe(self).options.intersection([true, false]).any?
        self.errors.add(:base,
                        "`options` must not include booleans. Please wrap values such as 'yes', and 'true' in quotes",
                        docs: "#{ConfigurationBase::DOCS_URL}#bodyi-options-must-not-include-booleans-please-wrap-values-such-as-yes-and-true-in-quotes")
      end
    end

    def id_is_string
      return if T.unsafe(self).label.try(:strip) == "" # if label is invalid whitespaces, don't bother to attempt to build an id
      validate_id(T.unsafe(self).id)
    end

    class_methods do
      def has_type?(input, type_string)
        if type_string == "Boolean"
          return [true, false].include?(input)
        elsif type_string == "String"
          return false if input.blank?
        end

        input&.class&.name == type_string
      end

      def has_types?(inputs, type_string)
        inputs.all? { |input| has_type?(input, type_string) }
      end

      def type_error_message(key, expected_type)
        msg = "`#{key}` must be of type #{expected_type}"
        msg += " and cannot be empty" if expected_type == "String"
        msg
      end

      def validate_required_attributes(attributes, record, key, value)
        return unless attributes.pluck(:id).include?(key)

        expected_type = attributes.find { |attr| attr[:id] == key }[:type]

        if value.nil?
          msg = "Required attribute key `#{key}` is missing"
          record.errors.add :base, msg, docs: "#{ConfigurationBase::DOCS_URL}#bodyi-required-attribute-key-value-is-missing"
        elsif expected_type == "Array" && value.is_a?(Array)
          expected_array_values_type = attributes.find { |attr| attr[:id] == key }[:array_of]

          if expected_array_values_type
            valid_values = has_types?(value, expected_array_values_type)

            unless valid_values
              record.errors.add(
                :base,
                "`#{key}` values must be of type #{expected_array_values_type}",
                docs: "#{ConfigurationBase::DOCS_URL}#bodyi-required-attribute-key-value-is-missing"
              )
            end
          end
        else
          valid_type = has_type?(value, expected_type)
          record.errors.add :base, type_error_message(key, expected_type), docs: "#{ConfigurationBase::DOCS_URL}#bodyi-label-must-be-a-string" unless valid_type
        end
      end

      def validate_optional_attributes(attributes, record, key, value)
        return unless attributes.pluck(:id).include?(key)

        expected_type = attributes.find { |attr| attr[:id] == key }[:type]
        valid_type = has_type?(value, expected_type)
        record.errors.add :base, type_error_message(key, expected_type), docs: "#{ConfigurationBase::DOCS_URL}#bodyi-label-must-be-a-string" unless valid_type
      end
    end
  end
end
