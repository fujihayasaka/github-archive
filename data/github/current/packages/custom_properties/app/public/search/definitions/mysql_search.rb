# typed: strict
# frozen_string_literal: true

class Search::Definitions::MysqlSearch
  SearchResult = T.type_alias do
    {
      items: T::Array[CustomProperties::IPropertyDefinition],
      total_entries: Integer,
      total_pages: Integer,
    }
  end

  PER_PAGE = 30
  TERMS = T.let(%i(managed-by org value-type required), T::Array[Symbol])
  ENUMERABLE_TERMS = T.let(%i(org value-type), T::Array[Symbol])

  # Initialize the search engine for the given scope
  #
  # source - The business or organization to search definitions in
  sig { params(source: CustomProperties::PropertySource, config: CustomProperties::ICustomPropertiesConfig).void }
  def initialize(source, config)
    @business = T.let(source, T.nilable(::Business)) if source.is_a?(::Business)
    @org = T.let(source, T.nilable(::Organization)) if source.is_a?(::Organization)
    @config = T.let(config, CustomProperties::ICustomPropertiesConfig)
  end

  # Public: search for property definitions using a standard query syntax
  #
  # q        - The query string
  # page     - The page number to return
  # per_page - The number of items per page
  #
  # Returns a hash with the page of results
  sig do
    params(
      q: T.nilable(String),
      page: Integer,
      per_page: Integer,
    ).returns(SearchResult)
  end
  def search(q, page = 1, per_page: PER_PAGE)
    parsed_query = Search::ParsedQuery.new(q, TERMS, nil, ENUMERABLE_TERMS)

    definitions = definitions_for_managed_by_and_org(parsed_query)
    definitions = filter_by_value_type(definitions, parsed_query)
    definitions = filter_by_text(definitions, parsed_query)
    definitions = filter_by_required(definitions, parsed_query) if GitHub.flipper[:custom_property_definitions_required_filter].enabled?
    definitions = definitions.order(:property_name, :source_type, :source_id)
    result = definitions.paginate(page: page, per_page: per_page)

    {
      items: result.to_a,
      total_entries: result.total_entries,
      total_pages: result.total_pages,
    }
  end

  private

  sig { params(parsed_query: Search::ParsedQuery).returns(T.untyped) }
  def definitions_for_managed_by_and_org(parsed_query)
    source = get_source_from_parsed_query(parsed_query)

    if @org.present?
      return [] if source == "enterprise" && @org.business.nil?
      return T.unsafe(@config.definition_class).for(@org.business) if source == "enterprise"
      return T.unsafe(@config.definition_class).defined_by(@org) if source == "organization"
      T.unsafe(@config.definition_class).for(@org)
    else
      biz_definitions = T.unsafe(@config.definition_class).for(@business)
      org_definitions = @config.definition_class.where(source_id: get_orgs_from_parsed_query(parsed_query), source_type: "org")

      return biz_definitions if source == "enterprise"
      return org_definitions if source == "organization"
      biz_definitions.or(org_definitions)
    end
  end

  sig { params(parsed_query: Search::ParsedQuery).returns(T.nilable(String)) }
  def get_source_from_parsed_query(parsed_query)
    qual = parsed_query.qualifiers[:"managed-by"]

    sources = %w(enterprise organization)

    if qual.must?
      sources &= qual.must.map(&:downcase)
    end

    if qual.must_not?
      sources -= qual.must_not.map(&:downcase)
    end

    return nil if sources.size != 1
    sources.first
  end

  sig { params(parsed_query: Search::ParsedQuery).returns(T::Array[Integer]) }
  def get_orgs_from_parsed_query(parsed_query)
    raise ArgumentError, "Must be called with an business-level search" if @business.nil?

    qual = parsed_query.qualifiers[:org]

    orgs = @business.organizations

    if qual.must? || qual.and_should?
      combined_logins = combine_must_and_should(qual)
      orgs = orgs.where(login: combined_logins)
    end

    if qual.must_not?
      orgs = orgs.where.not(login: qual.must_not)
    end

    orgs.pluck(:id)
  end

  sig { params(definitions: T.untyped, parsed_query: Search::ParsedQuery).returns(T.untyped) }
  def filter_by_text(definitions, parsed_query)
    text = parsed_query.query
    return definitions if text.blank?

    text.split(/\s+/).uniq.each do |word|
      definitions = definitions.where("property_name LIKE ?", "%#{word}%")
    end

    definitions
  end

  sig { params(definitions: T.untyped, parsed_query: Search::ParsedQuery).returns(T.untyped) }
  def filter_by_value_type(definitions, parsed_query)
    qual = parsed_query.qualifiers[:"value-type"]

    types = T.unsafe(@config.definition_class).value_types.values
    combined_types = combine_must_and_should(qual)
    if combined_types.any?
      types &= combined_types.map { |n| number_from_type(n) }.compact
    end

    if qual.must_not?
      types -= qual.must_not.map { |n| number_from_type(n) }.compact
    end

    return definitions unless types.any?
    return definitions if types.length == T.unsafe(@config.definition_class).value_types.length

    definitions.where(value_type: types)
  end

  sig { params(definitions: T.untyped, parsed_query: Search::ParsedQuery).returns(T.untyped) }
  def filter_by_required(definitions, parsed_query)
    qual = parsed_query.qualifiers[:required]
    values = qual.must? ? qual.must : qual.must_not
    return definitions unless %w[true false].include?(values&.first)

    condition = values.first == "true"
    qual.must? ? definitions.where(required: condition) : definitions.where.not(required: condition)
  end

  sig { params(type: String).returns(T.nilable(Integer)) }
  def number_from_type(type)
    type.downcase!
    type = "string" if type == "text"
    T.unsafe(@config.definition_class).value_types[type]
  end

  sig { params(qual: T.untyped).returns(T::Array[T.untyped]) }
  def combine_must_and_should(qual)
    (qual.must || []) + (qual.and_should&.flatten || [])
  end
end
