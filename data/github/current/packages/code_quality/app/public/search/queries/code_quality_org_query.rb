# typed: strict
# frozen_string_literal: true

class Search::Queries::CodeQualityOrgQuery < Search::Queries::SecurityCenter::Base
  QUALIFIER_HAS = :has
  QUALIFIER_NO = :no
  QUALIFIER_RELIABILITY_SCORE = :"reliability-score"
  QUALIFIER_MAINTAINABILITY_SCORE = :"maintainability-score"
  QUALIFIER_TOPIC = :topic
  QUALIFIER_TEAM = :team
  QUALIFIER_VISIBILITY = :visibility
  QUALIFIER_SORT = :sort
  PROPERTIES = Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT

  QUALIFIERS = T.let([
    QUALIFIER_HAS,
    QUALIFIER_NO,
    QUALIFIER_RELIABILITY_SCORE,
    QUALIFIER_MAINTAINABILITY_SCORE,
    QUALIFIER_TEAM,
    QUALIFIER_TOPIC,
    QUALIFIER_VISIBILITY,
    QUALIFIER_SORT,
    PROPERTIES
  ].freeze, T::Array[Symbol])

  HAS_VALUES = %w[standard-findings ai-findings].freeze
  NO_VALUES = %w[standard-findings ai-findings].freeze

  VISIBILITY_VALUES = %w[public private internal].freeze

  CUSTOM_PROPERTIES_PREFIX = T.let("props.".freeze, String)

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
    return false if has_conflicting_values?
    return false if self.class.has_qualifiers_without_value?(raw_query)
    return false if has_conflicting_has_no?
    return false unless has_valid_has?
    return false unless has_valid_no?
    return false unless has_valid_reliability_score?
    return false unless has_valid_maintainability_score?
    return false unless has_valid_visibility?
    true
  end

  sig { returns(T::Boolean) }
  def has_valid_has?
    has_values.all? { |h| HAS_VALUES.include?(h) }
  end

  sig { returns(T::Boolean) }
  def has_valid_no?
    no_values.all? { |n| NO_VALUES.include?(n) }
  end

  sig { returns(T::Boolean) }
  def has_conflicting_has_no?
    has = get_values_for_qualifier(QUALIFIER_HAS)
    no = get_values_for_qualifier(QUALIFIER_NO)

    (has & no).any?
  end

  sig { returns(T::Array[String]) }
  memoize def reliability_score
    get_values_for_qualifier(QUALIFIER_RELIABILITY_SCORE)
  end

  sig { returns(T.nilable(T::Array[T.any(Symbol, Integer)])) }
  memoize def reliability_score_filter
    grade_filter(reliability_score)
  end

  sig { returns(T::Boolean) }
  def has_valid_reliability_score?
    reliability_score.empty? || reliability_score_filter.present?
  end

  sig { returns(T::Array[String]) }
  memoize def maintainability_score
    get_values_for_qualifier(QUALIFIER_MAINTAINABILITY_SCORE)
  end

  sig { returns(T.nilable(T::Array[T.any(Symbol, Integer)])) }
  memoize def maintainability_score_filter
    grade_filter(maintainability_score)
  end

  sig { returns(T::Boolean) }
  memoize def has_valid_maintainability_score?
    maintainability_score.empty? || maintainability_score_filter.present?
  end

  sig { returns(T.any(Symbol, Integer)) }
  memoize def standard_findings_filter
    findings_filter("standard-findings")
  end

  sig { returns(T.any(Symbol, Integer)) }
  memoize def ai_findings_filter
    findings_filter("ai-findings")
  end

  sig { returns(T::Array[String]) }
  memoize def topics
    get_values_for_qualifier(QUALIFIER_TOPIC)
  end

  sig { returns(T::Array[String]) }
  memoize def excluded_topics
    get_values_for_qualifier(negate_qualifier(QUALIFIER_TOPIC))
  end

  sig { returns(T::Array[String]) }
  memoize def team_names
    get_values_for_qualifier(QUALIFIER_TEAM)
  end

  sig { returns(T::Array[String]) }
  memoize def excluded_team_names
    get_values_for_qualifier(negate_qualifier(QUALIFIER_TEAM))
  end

  sig { returns(T::Array[String]) }
  memoize def visibility_values
    get_values_for_qualifier(QUALIFIER_VISIBILITY).map(&:downcase)
  end

  sig { returns(T::Array[String]) }
  memoize def excluded_visibility_values
    get_values_for_qualifier(negate_qualifier(QUALIFIER_VISIBILITY)).map(&:downcase)
  end

  sig { returns(T::Boolean) }
  def has_valid_visibility?
    (visibility_values + excluded_visibility_values).all? { |v| VISIBILITY_VALUES.include?(v) }
  end

  sig { returns(T.nilable(T.any(Symbol, Integer))) }
  memoize def sort_order
    value = get_values_for_qualifier(QUALIFIER_SORT).map(&:downcase).first
    return nil unless value.present?

    sort_enum(value)
  end

  sig { returns(T::Hash[String, T.any(String, T::Array[String])]) }
  memoize def custom_properties_qualifiers
    parsed_query = self.class.parse(@raw_query)
    parsed_query.select do |qualifier, _|
      qualifier.delete_prefix("-").start_with?(CUSTOM_PROPERTIES_PREFIX)
    end
  end

  sig { returns(String) }
  memoize def custom_properties_query_string
    self.class.to_s(custom_properties_qualifiers)
  end

  private

  sig { returns(T::Array[String]) }
  memoize def has_values
    get_values_for_qualifier(QUALIFIER_HAS).map(&:downcase)
  end

  sig { returns(T::Array[String]) }
  memoize def no_values
    get_values_for_qualifier(QUALIFIER_NO).map(&:downcase)
  end

  sig { params(value: T::Array[String]).returns(T.nilable(T::Array[T.any(Symbol, Integer)])) }
  def grade_filter(value)
    return [] unless value.present?

    value = value.map(&:downcase)

    value.filter_map do |v|
      case v
      when "excellent"
        Turboquality::Proto::Grade::GRADE_A
      when "good"
        Turboquality::Proto::Grade::GRADE_B
      when "fair"
        Turboquality::Proto::Grade::GRADE_C
      when "needs-improvement"
        Turboquality::Proto::Grade::GRADE_D
      else
        nil
      end
    end
  end

  sig { params(value: T.nilable(String)).returns(T.any(Symbol, Integer)) }
  def sort_enum(value)
    case value
    when "last-activity-desc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_LAST_ACTIVITY_DESC
    when "last-activity-asc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_LAST_ACTIVITY_ASC
    when "repository-name-desc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_REPOSITORY_NAME_DESC
    when "repository-name-asc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_REPOSITORY_NAME_ASC
    when "reliability-desc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_RELIABILITY_DESC
    when "reliability-asc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_RELIABILITY_ASC
    when "maintainability-desc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_MAINTAINABILITY_DESC
    when "maintainability-asc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_MAINTAINABILITY_ASC
    when "standard-findings-count-desc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_STANDARD_FINDINGS_COUNT_DESC
    when "standard-findings-count-asc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_STANDARD_FINDINGS_COUNT_ASC
    when "ai-findings-count-desc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_AI_FINDINGS_COUNT_DESC
    when "ai-findings-count-asc"
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_AI_FINDINGS_COUNT_ASC
    else
      Turboquality::Proto::RepositoryStatisticsSortOrder::REPOSITORY_STATISTICS_SORT_ORDER_NONE
    end
  end

  sig { params(qualifier: String).returns(T.any(Symbol, Integer)) }
  def findings_filter(qualifier)
    return Turboquality::Proto::FindingsFilter::FINDINGS_FILTER_SOME_FINDINGS if has_values.include?(qualifier)
    return Turboquality::Proto::FindingsFilter::FINDINGS_FILTER_NO_FINDINGS if no_values.include?(qualifier)

    Turboquality::Proto::FindingsFilter::FINDINGS_FILTER_NONE
  end

  sig { returns(T::Boolean) }
  def has_conflicting_values?
    self.class.has_conflicting_values?(raw_query)
  end

  sig { params(qualifier: Symbol).returns(T::Array[String]) }
  def get_values_for_qualifier(qualifier)
    self.class.get_qualified_values(raw_query, qualifier)
  end

  sig { params(qualifier: Symbol).returns(Symbol) }
  def negate_qualifier(qualifier)
    self.class.negate_qualifier(qualifier)
  end
end
