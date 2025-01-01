# typed: strict
# frozen_string_literal: true

module Search::Definitions::MysqlSearch
  SearchResult = T.type_alias do
    {
      items: T::Array[CustomProperties::IPropertyDefinition],
      total_entries: Integer,
      total_pages: Integer,
    }
  end

  PER_PAGE = 30
  TERMS = T.let(%i(managed-by org), T::Array[Symbol])
  ENUMERABLE_TERMS = T.let(%i(org), T::Array[Symbol])

  # Public: search for property definitions using a standard query syntax
  #
  # business - The business to search for definitions in
  # q        - The query string
  # page     - The page number to return
  # per_page - The number of items per page
  #
  # Returns a hash with the page of results
  sig do
    params(
      business: ::Business,
      q: T.nilable(String),
      page: Integer,
      per_page: Integer,
    ).returns(SearchResult)
  end
  def self.search(business, q, page = 1, per_page: PER_PAGE)
    parsed_query = Search::ParsedQuery.new(q, TERMS, nil, ENUMERABLE_TERMS)

    definitions = definitions_for_managed_by_and_org(business, parsed_query)
    definitions = filter_by_text(definitions, parsed_query)
    definitions = definitions.order(:property_name, :source_type, :source_id)
    result = definitions.paginate(page: page, per_page: per_page)

    {
      items: result.to_a,
      total_entries: result.total_entries,
      total_pages: result.total_pages,
    }
  end

  sig { params(business: ::Business, parsed_query: Search::ParsedQuery).returns(T.untyped) }
  private_class_method def self.definitions_for_managed_by_and_org(business, parsed_query)
    biz_definitions = CustomPropertyDefinition.for(business)
    org_definitions = CustomPropertyDefinition.where(source_id: get_orgs_from_parsed_query(business, parsed_query), source_type: "org")

    source = get_source_from_parsed_query(parsed_query)

    return biz_definitions if source == "enterprise"
    return org_definitions if source == "organization"
    biz_definitions.or(org_definitions)
  end

  sig { params(parsed_query: Search::ParsedQuery).returns(T.nilable(String)) }
  private_class_method def self.get_source_from_parsed_query(parsed_query)
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

  sig { params(business: ::Business, parsed_query: Search::ParsedQuery).returns(T::Array[Integer]) }
  private_class_method def self.get_orgs_from_parsed_query(business, parsed_query)
    qual = parsed_query.qualifiers[:org]

    orgs = business.organizations

    if qual.must? || qual.and_should?
      combined_logins = (qual.must || []) + (qual.and_should&.flatten || [])
      orgs = orgs.where(login: combined_logins)
    end

    if qual.must_not?
      orgs = orgs.where.not(login: qual.must_not)
    end

    orgs.pluck(:id)
  end

  sig { params(definitions: T.untyped, parsed_query: Search::ParsedQuery).returns(T.untyped) }
  private_class_method def self.filter_by_text(definitions, parsed_query)
    return definitions if parsed_query.query.blank?

    definitions.where("property_name LIKE ?", "%#{parsed_query.query}%")
  end
end
