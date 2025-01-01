# typed: true
# frozen_string_literal: true

class SponsorsExploreFilterSet
  DEFAULT_SORT_BY = SponsorsExploreLoader::MOST_USED_SORT
  SORT_BY_VALUES = SponsorsHelper::MAINTAINER_SORT_OPTIONS.keys.to_set.freeze
  ECOSYSTEMS = Platform::Enums::DependencyGraphEcosystem.values.keys.to_set.freeze

  # Valid values in the `FilterOption` enum of the `github.sponsors.v1.ExploreFilterChange` schema:
  HYDRO_FILTER_OPTIONS = [
    :UNKNOWN,
    :ECOSYSTEM_UNKNOWN,
    :DIRECT_DEPENDENCIES_ONLY,
    :ECOSYSTEM_ALL,
    :ECOSYSTEM_CARGO,
    :ECOSYSTEM_COMPOSER,
    :ECOSYSTEM_GITHUB_ACTIONS,
    :ECOSYSTEM_GO,
    :ECOSYSTEM_MAVEN,
    :ECOSYSTEM_NPM,
    :ECOSYSTEM_NUGET,
    :ECOSYSTEM_PIP,
    :ECOSYSTEM_RUBYGEMS,
    :ECOSYSTEM_PUB,
  ].freeze

  # Public: Mapping of ecosystem filter options that are available for filtering sponsorable dependencies.
  #
  # See AdvisoryDB::Ecosystems for available ecosystems.
  ECOSYSTEM_NAMES = {
    nil => "All ecosystems",
    "RUST" => "Cargo",
    "COMPOSER" => "composer",
    "ACTIONS" => "GitHub Actions",
    "GO" => "go",
    "MAVEN" => "maven",
    "NPM" => "npm",
    "NUGET" => "nuget",
    "PIP" => "pip",
    "RUBYGEMS" => "RubyGems",
    "PUB" => "pub",
  }.freeze

  # Public: Get a list of ecosystem filters from URL parameters.
  #
  # params - URL parameters
  sig do
    params(params: T.any(ActionController::Parameters, T::Hash[Symbol, String])).returns(T::Array[String])
  end
  def self.ecosystems_from(params)
    ecosystems = []
    ecosystems += params[:ecosystems].split(",") if params[:ecosystems].present?
    ecosystems << params[:ecosystem] if params[:ecosystem].present?
    ecosystems.map(&:strip)
  end

  def self.hydro_ecosystem_filter_option_for(value:, label:)
    return :ECOSYSTEM_ALL if value.nil?
    suffix = label.gsub(/\s+/, "_").upcase
    filter_option = "ECOSYSTEM_#{suffix}".to_sym
    unless HYDRO_FILTER_OPTIONS.include?(filter_option)
      filter_option = :ECOSYSTEM_UNKNOWN
    end
    filter_option
  end

  # per_page - how many dependencies to show per page
  # sort_by - how to order the dependencies; defaults to the most used dependencies first
  # account_login - the login for the User or Organization whose dependencies are being explored
  # ecosystems - optional Array of String package managers to filter dependencies; see
  #              AdvisoryDB::Ecosystems.dependency_graph_supported for options
  # direct_only - Boolean indicating whether only direct dependencies should be included, versus including both
  #               direct and indirect dependencies; an indirect dependency is one that the owner isn't using
  #               in one of their own repos, but rather is a dependency of a dependency
  def initialize(page: 1, per_page: 30, sort_by: DEFAULT_SORT_BY, account_login: nil, ecosystems: [], direct_only: true)
    @page = (page || 1).to_i
    @per_page = (per_page || 30).to_i
    @sort_by = if SORT_BY_VALUES.include?(sort_by)
      sort_by
    else
      DEFAULT_SORT_BY
    end
    @account_login = account_login
    @ecosystems = if ecosystems
      ecosystems.compact_blank.sort.uniq.map(&:upcase).select { |ecosystem| ECOSYSTEMS.include?(ecosystem) }
    else
      []
    end
    @direct_only = !!direct_only
  end

  attr_reader :sort_by, :account_login, :ecosystems, :page, :per_page

  # Public: Are the results being filtered such that they might be limited?
  #
  # Returns a Boolean.
  def filtering?
    !direct_dependencies_only? || ecosystems.present?
  end

  def direct_dependencies_only?
    @direct_only
  end

  def eql?(other)
    return false unless other&.is_a?(self.class)
    other.query_args.eql?(query_args)
  end

  # Public: Get a new filter set that preserves sort order but removes any filters that might limit the results.
  # Does not change whose account's results are being viewed.
  #
  # Returns a SponsorsExploreFilterSet.
  def with_default_filters
    with(direct_only: true, page: 1, ecosystems: [])
  end

  # Public: Get a new filter set that's the same as this one but with the specified filters and sorting overridden.
  #
  # overrides - Hash of overrides to apply to this filter set; keys should be symbols
  #
  # Returns a SponsorsExploreFilterSet.
  def with(**overrides)
    args = {
      page: 1, # go back to the first page when changing filters or sorting
      per_page: per_page,
      sort_by: sort_by,
      account_login: account_login,
      ecosystems: ecosystems,
      direct_only: direct_dependencies_only?,
    }.merge(overrides)
    self.class.new(**args)
  end

  # Public: Get parameters to use in a Rails route helper to represent this filter set.
  #
  # Returns a Hash.
  def query_args
    args = {}
    args[:sort_by] = sort_by if sort_by.present? && sort_by != DEFAULT_SORT_BY
    args[:page] = page if page && page > 1
    args[:account] = account_login if account_login.present?
    args[:direct] = "0" unless direct_dependencies_only?
    if ecosystems.size == 1
      args[:ecosystem] = ecosystems.first
    elsif ecosystems.present?
      args[:ecosystems] = ecosystems.join(",")
    end
    args
  end

  def inspect
    to_s
  end

  # Public: Get an explanation of why there are no results due to this filter set being applied.
  #
  # account_is_viewer - Boolean indicating whether or not the current viewer is the same as the account whose
  #                     results are being shown
  #
  # Returns a human-readable String.
  def no_results_explanation(account_is_viewer:)
    subject = if account_is_viewer
      "You don't"
    else
      "#{account_login} does not"
    end
    adverb = if direct_dependencies_only?
      "directly"
    end
    ecosystems_phrase = if ecosystems.present?
      units = "ecosystem".pluralize(ecosystems.size)
      display_names = ecosystems.map do |ecosystem|
        ECOSYSTEM_NAMES[ecosystem] || ecosystem
      end
      "in the #{display_names.to_sentence} #{units}"
    end
    parts = [
      subject,
      adverb,
      "depend on any repositories",
      ecosystems_phrase,
      "whose maintainers can be sponsored.",
    ]
    parts.compact.join(" ")
  end

  def to_s
    query_args.to_query
  end
end
