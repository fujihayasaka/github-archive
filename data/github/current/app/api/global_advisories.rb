# typed: true
# frozen_string_literal: true

class Api::GlobalAdvisories < Api::App
  include FeatureFlagHelper
  include Api::App::AdvisoryPaginationHelpers
  include AdvisoryDB::GlobalAdvisoriesApiHelper

  API_FILTERS = %w[
    affects credits cve_id cwes ecosystem ghsa_id
    is_withdrawn keywords modified published severity
    type updated
  ]

  def deliver_global_advisory(advisory, current_user, status: 200)
    options = {
      current_user:,
      last_modified: calc_last_modified_for_object(advisory),
      status: status,
    }

    deliver :global_advisory_hash, advisory, options
  end

  def deliver_global_advisories(advisories, current_user, status: 200)
    options = {
      current_user:,
      last_modified: calc_last_modified(advisories),
      status: status,
    }

    deliver :global_advisories_hash, { advisories: advisories }, options
  end

  get "/advisories/:ghsa_id", operation_id: "security-advisories/get-global-advisory" do
    advisory = SecurityAdvisory.find_by(ghsa_id: params[:ghsa_id])

    control_access :get_global_advisory,
      resource: advisory,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_global_advisory advisory, current_user
  end

  get "/advisories", operation_id: "security-advisories/list-global-advisories" do
    control_access :get_global_advisories,
      resource: AdvisoryDB::GlobalAdvisoriesResource.new(current_user, anonymous_request?),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    receive_with_openapi
    record_params_dogstats

    query_start_time = GitHub::Dogstats.monotonic_time
    if use_ar?
      advisories = filter_with_ar
      advisories = sort_and_paginate_ar advisories
    else
      advisories = filter_with_es
    end

    elapsed = GitHub::Dogstats.duration(query_start_time)
    backend = use_ar? ? "ar" : "es"
    GitHub.dogstats.distribution("global_advisory_api.get_advisories.duration", elapsed, tags: ["backend:#{backend}"])

    deliver_global_advisories advisories, current_user
  rescue Platform::Errors::Cursor,
    Platform::Errors::DuplicateFirstLastPaginationBoundaries,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end

  def filter_with_es
    query_string = build_es_filters

    direction = (params[:direction]&.upcase == "ASC") ? "asc" : "desc"

    order = case params[:sort]&.upcase
    when "UPDATED"
      "updated"
    when "EPSS_PERCENTAGE"
      "epss_percentage"
    when "EPSS_PERCENTILE"
      "epss_percentile"
    else
      "published"
    end

    per_page = (params[:per_page].presence || DEFAULT_CURSOR_PAGINATION_RESULT_SIZE).to_i

    query = Search::QueryHelper.new(query_string, "Vulnerabilities",
      current_user: current_user,
      remote_ip: remote_ip,
      page: current_page,
      per_page: [per_page, 100].min, # allow max 100 per page
      sort: [order, direction],
      is_api_query: true,
    ).vulnerability_query

    results = query.execute.results
    results.map { |advisory| advisory["_model"] }
  end

  def build_es_filters
    q = ""

    validate_date_params!

    epss_filters = [:epss_percentage, :epss_percentile]
    raw_filters  = [:ghsa_id, :cve_id, :keywords]
    enum_filters = [:type, :ecosystem]
    date_filters = [:modified, :published, :updated]
    list_filters = [:credits, :affects, :cwes]

    params.each do |key, value|
      filter = key.to_sym
      if raw_filters.include?(filter)
        q = add_filter(q, value)
      elsif epss_filters.include?(filter)
        q = add_filter(q, "#{filter}:#{value}")
      elsif enum_filters.include?(filter)
        q = add_filter(q, "#{filter}:#{value}")
      elsif date_filters.include?(filter)
        parse_date_parameter(value) # ensure valid date/range
        q = add_filter(q, "#{filter}:#{value}")
      elsif list_filters.include?(filter)
        q = add_filter_list(q, filter, value)
      elsif filter == :is_withdrawn
        q = if params[:is_withdrawn] == "true"
          add_filter(q, "is:withdrawn")
        else
          add_filter(q, "-is:withdrawn")
        end
      elsif filter == :severity
        severity = value == "medium" ? "moderate" : value
        q = add_filter(q, "severity:#{severity}")
      end
    end

    q
  end

  def filter_with_ar
    ensure_non_conflicting_cursor_params!
    validate_date_params!

    is_base_query = (params.keys - SORT_PARAMS).empty?
    return Vulnerability.disclosed.has_been_reviewed.where.not(classification: :malware) if is_base_query

    query = Vulnerability.disclosed

    if params.key?(:severity) # `index_vulnerabilities_on_severity`
      severity = case params[:severity]
      when "medium"
        "moderate"
      when "unknown"
        nil
      else
        params[:severity]
      end

      query = query.severity(severity)
    end

    if params.key?(:ghsa_id) # `index_vulnerabilities_on_ghsa_id`
      deliver_error!(400, message: "Invalid GHSA ID") unless AdvisoryDB.valid_ghsa_id_input_pattern.match?(params[:ghsa_id])

      query = query.where(ghsa_id: sanitize_param_value(params[:ghsa_id]))
    end

    if params.key?(:cve_id) # `index_vulnerabilities_on_cve_id`
      query = query.where(cve_id: sanitize_param_value(params[:cve_id]))
    end

    if params.key?(:type) # no index on status or classification
      type = params[:type]

      case type
      when "malware"
        query = query.where(classification: :malware)
      when "unreviewed"
        query = query.unreviewed
      when "reviewed"
        query = query.has_been_reviewed.where.not(classification: :malware)
      end
    else
      # ensure queries without a type specified return no malware advisories by default
      query = query.where.not(classification: :malware)
    end

    if params.key?(:is_withdrawn) # no index on status or classfication
      if params[:is_withdrawn] == "true"
        query = query.where(status: :withdrawn)
      else
        query = query.where.not(status: :withdrawn)
      end
    end

    if params.key?(:ecosystem) # `index_vulnerable_version_ranges_on_ecosystem`
      query = query.where(vulnerable_version_ranges: { ecosystem: params[:ecosystem] }).distinct
    end

    if params.key?(:published)  # `index_vulnerabilities_on_published_at`
      published = params[:published]
      date_query = parse_date_parameter(published)
      query = query.where(published_at: date_query)
    end

    if params.key?(:updated) # `index_vulnerabilities_on_updated_at`
      updated = params[:updated]
      date_query = parse_date_parameter(updated)
      query = query.where(updated_at: date_query)
    end

    if params.key?(:modified) # both the above keys
      modified = params[:modified]
      date_query = parse_date_parameter(modified)
      query = query.where(updated_at: date_query).or(query.where(published_at: date_query))
    end

    if params.key?(:cwes) # `index_on_source_and_cwe` (`source_type`,`source_id`,`cwe_id`)
      cwes = list_to_array(params[:cwes]).map { |cwe| "CWE-#{cwe.to_i}" }

      cwe_db_ids = CWE.where(cwe_id: cwes).pluck(:id) # `index_cwes_on_cwe_id`
      query = query.joins(:cwe_references).where(cwe_references: { cwe_id: cwe_db_ids })
    end

    if params.key?(:affects) # `index_vulnerable_version_ranges_on_affects`
      packages = list_to_array(params[:affects]).uniq.map { |p| sanitize_param_value(p) }

      if querying_package_versions?(params[:affects]) || packages.count > MAX_PACKAGES_PER_BATCH
        vuln_ids = vuln_ids_affecting_packages(affects: packages, base_scope: query, current_user: current_user, request_params: params, backend: "ar")
        query = query.where(id: vuln_ids)
      else
        query = query.where(vulnerable_version_ranges: { affects: packages })
      end
    end

    if params.key?(:epss_percentage)
      query  = query.joins(:cve_epss).where(cve_epss: { percentage: params[:epss_percentage] })
    end

    if params.key?(:epss_percentile)
      query  = query.joins(:cve_epss).where(cve_epss: { percentile: params[:epss_percentile] })
    end

    query
  end

  def sort_and_paginate_ar(advisories)
    advisories = sort_advisories(advisories, sort_by: params[:sort] || :published, direction: params[:direction] || :desc, current_user: current_user)

    advisories_platform_relation = paginate_advisories(advisories, params)
    advisories = advisories_platform_relation.edge_nodes.sync
    set_cursor_based_pagination_headers(advisories_platform_relation) if advisories.any?

    advisories
  end

  sig { params(query: String, filter: T.nilable(String)).returns(String) }
  def add_filter(query, filter)
    return query unless filter

    if query.blank?
      return "#{filter}"
    end

    "#{query} #{filter}"
  end

  sig { params(query: String, filter: T.any(String, Symbol), list: T.any(Array, String)).returns(String) }
  def add_filter_list(query, filter, list)
    filter_qualifiers = { credits: :credit, affects: :affects, cwes: :cwe }

    q = ""

    items = list_to_array(list)

    items.each do |item|
      q = add_filter(q, "#{filter_qualifiers[filter]}:#{item}")
    end

    q
  end

  private

  def validate_date_params!
    if params.key?(:modified) && (params.key?(:published) || params.key?(:updated))
      deliver_error!(422, message: "The `modified` parameter cannot be used with `published` or `updated`.")
    end
  end

  def ensure_non_conflicting_cursor_params!
    if params.key?(:after) && params.key?(:before)
      deliver_error!(400, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  def record_params_dogstats
    metric_name = "global_advisories_api.get_advisories.filters"

    # filter out random parameters users may pass in
    filters = (params.keys).intersection(API_FILTERS)

    if filters.empty?
      GitHub.dogstats.increment(metric_name, tags: ["filter:none"])
    end

    filters.each do |key|
      GitHub.dogstats.increment(metric_name, tags: ["filter:#{key}"])
    end
  end

  def sanitize_param_value(value)
    value&.split&.join
  end

  # This method helps us parse the date parameters and return a range that is easy to give ActiveRecord
  sig { params(value: String).returns(T.any(Range, DateTime)) }
  def parse_date_parameter(value)
    date_time_pattern = /\d(\d|[TZ\-:\+])+/
    day_pattern = /\A\d{4}-\d{2}-\d{2}\z/

    dot_range_pattern = /\A(?<date1>#{date_time_pattern.source})\.\.(?<date2>#{date_time_pattern.source})\z/
    comparator_pattern = /\A(?<comparator>[><]=?)(?<date>#{date_time_pattern.source})\z/
    equality_pattern = /\A#{date_time_pattern.source}\z/

    if value.match(equality_pattern)
      date_time = DateTime.parse(value) # will raise Date::Error if invalid

      if value.match?(day_pattern)
        return date_time.all_day
      end

      date_time
    elsif range = value.match(comparator_pattern)
      comparator, date = range[:comparator], range[:date]
      date_time = DateTime.parse(date)

      date_range = case comparator
      when "<"
        (...date_time)
      when "<="
        (..date_time)
      when ">"
        # If given a date with no time, we want to exclude the entire day.
        date&.match?(day_pattern) ? (date_time.end_of_day...) : (date_time...)
      when ">="
        (date_time..)
      end

      date_range
    elsif range = value.match(dot_range_pattern)
      date1, date2 = range[:date1], range[:date2]

      date_time1 = DateTime.parse(date1)
      # If given a date with no time, we want to include the entire day.
      date_time2 = date2&.match?(day_pattern) ? DateTime.parse(date2).end_of_day : DateTime.parse(date2)

      (date_time1..date_time2)
    else
      raise Date::Error
    end
  rescue Date::Error
    deliver_error!(422, message: "The date input '#{value}' is invalid.")
  end

  def use_ar?
    feature_enabled_globally_or_for_user?(feature_name: :global_advisories_api_use_ar) || GitHub.enterprise?
  end
end
