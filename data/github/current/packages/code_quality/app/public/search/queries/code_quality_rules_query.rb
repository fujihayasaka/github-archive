# typed: strict
# frozen_string_literal: true

class Search::Queries::CodeQualityRulesQuery < Search::Queries::SecurityCenter::Base
  QUALIFIER_SEVERITY = :severity
  QUALIFIER_CATEGORY = :category
  QUALIFIER_LANGUAGE = :language
  QUALIFIER_IS = :is

  QUALIFIERS = T.let([
    QUALIFIER_SEVERITY,
    QUALIFIER_CATEGORY,
    QUALIFIER_LANGUAGE,
    QUALIFIER_IS,
  ].freeze, T::Array[Symbol])

  class << self
    protected

    sig { returns(T::Array[Symbol]) }
    def allowed_qualifiers
      QUALIFIERS
    end

    sig { returns(T::Boolean) }
    def preserve_case
      true
    end
  end

  sig { returns(String) }
  attr_reader :raw_query

  sig { params(raw_query: String).void }
  def initialize(raw_query = "")
    @raw_query = raw_query
  end

  sig { returns(T::Boolean) }
  def is_valid?
    return true if raw_query.blank?
    return false if self.class.has_qualifiers_without_value?(raw_query)
    return false unless has_valid_severity?
    return false unless has_valid_category?
    return false unless has_valid_language?
    return false unless has_valid_finding_state?
    true
  end

  sig { returns(T::Array[String]) }
  memoize def severity
    get_values_for_qualifier(QUALIFIER_SEVERITY)
  end

  sig { returns(T::Array[Integer]) }
  memoize def severity_filter
    return [] if severity.empty?

    severity.filter_map do |value|
      GitHub::Turboquality.to_rule_severity(value) if value.present?
    end
  end

  sig { returns(T::Boolean) }
  def has_valid_severity?
    severity.empty? || severity_filter.size == severity.size
  end

  sig { returns(T::Array[String]) }
  memoize def category
    get_values_for_qualifier(QUALIFIER_CATEGORY)
  end

  sig { returns(T::Array[Integer]) }
  memoize def category_filter
    return [] if category.empty?

    category.filter_map do |value|
      GitHub::Turboquality.to_rule_category(value) if value.present?
    end
  end

  sig { returns(T::Boolean) }
  def has_valid_category?
    category.empty? || category_filter.size == category.size
  end

  sig { returns(T::Array[String]) }
  memoize def language
    get_values_for_qualifier(QUALIFIER_LANGUAGE)
  end

  sig { returns(T::Array[Integer]) }
  memoize def language_filter
    return [] if language.empty?

    language.filter_map do |value|
      GitHub::Turboquality.to_rule_language(value) if value.present?
    end
  end

  sig { returns(T::Boolean) }
  def has_valid_language?
    language.empty? || language_filter.size == language.size
  end

  sig { returns(T::Array[String]) }
  memoize def finding_state
    get_values_for_qualifier(QUALIFIER_IS)
  end

  sig { returns(T::Array[Integer]) }
  memoize def finding_state_filter
    return [] if finding_state.empty?

    finding_state.filter_map do |value|
      GitHub::Turboquality.to_finding_state(value) if value.present?
    end
  end

  sig { returns(T::Boolean) }
  def has_valid_finding_state?
    finding_state.empty? || finding_state_filter.size == finding_state.size
  end

  sig { returns(T::Array[String]) }
  memoize def rule_name
    self.class.get_unqualified_values(raw_query)
  end

  sig { returns(T.nilable(String)) }
  memoize def rule_name_filter
    rule_name.join(" ").presence
  end

  private

  sig { params(qualifier: Symbol).returns(T::Array[String]) }
  def get_values_for_qualifier(qualifier)
    self.class.get_qualified_values(raw_query, qualifier)
  end
end
