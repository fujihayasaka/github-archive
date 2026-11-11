# typed: strict
# frozen_string_literal: true

module TriageAgent
  # Storage-agnostic value object that holds allowed/disallowed lists for
  # triage suggestions and performs filtering. Can be constructed from any
  # config source — callers interact only with this class, never with the
  # parser directly.
  class Allowlist
    sig { returns(T::Boolean) }
    attr_reader :comment_enabled

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :allowed_labels

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :disallowed_labels

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :allowed_types

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :disallowed_types

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :allowed_fields

    sig { returns(T.nilable(T::Array[String])) }
    attr_reader :disallowed_fields

    sig do
      params(
        comment_enabled: T::Boolean,
        allowed_labels: T.nilable(T::Array[String]),
        disallowed_labels: T.nilable(T::Array[String]),
        allowed_types: T.nilable(T::Array[String]),
        disallowed_types: T.nilable(T::Array[String]),
        allowed_fields: T.nilable(T::Array[String]),
        disallowed_fields: T.nilable(T::Array[String])
      ).void
    end
    def initialize(
      comment_enabled: true,
      allowed_labels: nil,
      disallowed_labels: nil,
      allowed_types: nil,
      disallowed_types: nil,
      allowed_fields: nil,
      disallowed_fields: nil
    )
      @comment_enabled = comment_enabled
      @allowed_labels = allowed_labels
      @disallowed_labels = disallowed_labels
      @allowed_types = allowed_types
      @disallowed_types = disallowed_types
      @allowed_fields = allowed_fields
      @disallowed_fields = disallowed_fields
    end

    # Filters labels against the allowlist/disallowlist. See filter_string_list for rules.
    sig { params(labels: T::Array[String]).returns(T::Array[String]) }
    def filter_labels(labels)
      return labels if labels.empty?
      return labels unless labels_restricted?

      filter_string_list(labels, allowed: @allowed_labels, disallowed: @disallowed_labels)
    end

    # Filters issue type against the allowlist/disallowlist.
    # Returns the type unchanged if permitted, or nil if blocked.
    sig { params(type: T.nilable(String)).returns(T.nilable(String)) }
    def filter_type(type)
      return type if type.nil?
      return type unless types_restricted?

      filter_string_list([type], allowed: @allowed_types, disallowed: @disallowed_types).first
    end

    # Filters issue fields by name against the allowlist/disallowlist.
    # Each field hash must have a :name key. Fields with blocked names are removed.
    sig do
      params(
        fields: T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]]
      ).returns(T::Array[T::Hash[Symbol, T.nilable(T.any(String, Integer, Float))]])
    end
    def filter_fields(fields)
      return fields if fields.empty?
      return fields unless fields_restricted?

      field_names = fields.filter_map { |f| f[:name]&.to_s }
      allowed_names = filter_string_list(field_names, allowed: @allowed_fields, disallowed: @disallowed_fields)
      allowed_names_set = allowed_names.map(&:downcase).to_set

      fields.select { |f| allowed_names_set.include?(f[:name].to_s.downcase) }
    end

    # Uses .present? for disallowed so that an empty array (blocked: []) is
    # treated as unrestricted
    sig { returns(T::Boolean) }
    def labels_restricted?
      !@allowed_labels.nil? || @disallowed_labels.present?
    end

    sig { returns(T::Boolean) }
    def types_restricted?
      !@allowed_types.nil? || @disallowed_types.present?
    end

    sig { returns(T::Boolean) }
    def fields_restricted?
      !@allowed_fields.nil? || @disallowed_fields.present?
    end

    sig { returns(T::Boolean) }
    def any_restrictions?
      labels_restricted? || types_restricted? || fields_restricted?
    end

    private

    # Generic filter for a list of strings against an allowed/disallowed pair.
    # 1. If allowed is set, only values on the allowlist pass (include-list).
    # 2. If disallowed is set, values on the disallowlist are removed (exclude-list).
    # 3. When both are set, both are applied: allowed first, then disallowed.
    #    This means disallowed takes precedence (a value in both lists is removed).
    # 4. If neither is set, all values pass through unchanged.
    # All comparisons are case-insensitive.
    sig do
      params(
        values: T::Array[String],
        allowed: T.nilable(T::Array[String]),
        disallowed: T.nilable(T::Array[String])
      ).returns(T::Array[String])
    end
    def filter_string_list(values, allowed:, disallowed:)
      return values if values.empty?
      return [] if allowed&.empty?

      result = values

      if allowed
        allowed_set = allowed.map(&:downcase).to_set
        result = result.select { |v| allowed_set.include?(v.downcase) }
      end

      if disallowed&.any?
        disallowed_set = disallowed.map(&:downcase).to_set
        result = result.reject { |v| disallowed_set.include?(v.downcase) }
      end

      result
    end
  end
end
