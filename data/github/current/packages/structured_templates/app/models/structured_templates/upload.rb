# typed: true
# frozen_string_literal: true

module StructuredTemplates
  class Upload
    include ActiveModel::Validations
    include StructuredTemplates::ValidationHelpers

    REQUIRED_ATTRIBUTES = [{ id: :label, type: "String" }].freeze

    OPTIONAL_ATTRIBUTES = [
      { id: :description, type: "String" },
    ].freeze

    OPTIONAL_VALIDATIONS = [{ id: :required, type: "Boolean" }, { id: :accept, type: "String" }, { id: :validations, type: "Hash" }].freeze

    validates_each :label do |record, key, value|
      validate_required_attributes(REQUIRED_ATTRIBUTES, record, key, value)
    end

    validates_each :description, :value do |record, key, value|
      next if value.nil?
      validate_optional_attributes(OPTIONAL_ATTRIBUTES, record, key, value)
    end

    validates_each :validations, :required, :accept do |record, key, value|
      next if value.nil?
      validate_optional_attributes(OPTIONAL_VALIDATIONS, record, key, value)
    end

    validate :no_extra_keys
    validate :no_extra_attributes
    validate :id_is_string
    validate :no_forbidden_label
    validate :valid_accept_string

    attr_reader :type, :id, :label, :description, :required, :accept, :input, :validations, :auto_id
    attr_accessor :value

    def initialize(input:)
      @input = input
      @type = @input.dig("type")

      @label = @input.dig("attributes", "label")
      @id, @auto_id = build_id(@input, @label)
      @description = @input.dig("attributes", "description")
      @required = false_if_undefined(@input, "validations", "required")
      @validations = @input.dig("validations")
      @accept = @validations.is_a?(Hash) ? @validations.dig("accept") : nil
    end

    def platform_type_name
      "IssueFormElementUpload"
    end

    private

    def valid_accept_string
      return unless @accept.is_a?(String)

      valid_extensions = (RepositoryFile.user_allowed_content_extensions + UserAsset.user_allowed_content_extensions).uniq
      invalid_extensions = @accept.split(",").map(&:strip) - valid_extensions

      if invalid_extensions.any?
        errors.add(:accept, "contains invalid file extensions: #{invalid_extensions.join(', ')}", docs: ConfigurationBase::DOCS_URL)
      end
    end

    def no_extra_attributes
      check_extraneous_attributes(REQUIRED_ATTRIBUTES + OPTIONAL_ATTRIBUTES, @input["attributes"]&.keys)
    end
  end
end
