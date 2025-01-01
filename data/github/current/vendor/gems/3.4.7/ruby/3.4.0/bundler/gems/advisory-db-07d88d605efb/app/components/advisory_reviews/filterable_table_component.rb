# frozen_string_literal: true

module AdvisoryReviews
  class FilterableTableComponent < ApplicationComponent
    include HasCurationState
    include HasPagination
    include HasSearching
    include HasLabelFiltering
    include HasSeverities

    attr_reader :sort, :sort_by, :curation_state, :curator, :source, :query, :ecosystem, :label_ids, :severity, :campaign, :campaign_review_state

    delegate :ecosystems, :ecosystem_color, :ecosystem_label, to: :AdvisoryDB

    CURATION_STATES = %w[
      waiting
      open
      open_create
      open_update
      ready
      ready_to_publish
      ready_to_withdraw
      published
      published_unreviewed
      published_reviewed
      withdrawn
      closed
    ].freeze

    SORTABLE_FIELDS = %w[
      date
      severity
    ].freeze
    DEFAULT_SORTABLE_FIELD = "date"

    SORT_DIRECTIONS = %w[asc desc].freeze
    DEFAULT_SORT_DIRECTION = "asc"

    def initialize(sort:, sort_by:, state:, curator:, source:, page:, query:, ecosystem:, label_ids:, severity:, campaign: nil, campaign_review_state: nil)
      @sort = SORT_DIRECTIONS.include?(sort) ? sort : DEFAULT_SORT_DIRECTION
      @sort_by = SORTABLE_FIELDS.include?(sort_by) ? sort_by : DEFAULT_SORTABLE_FIELD
      @curation_state = state || "open"
      @curator = curator.presence || "all"
      @source = source || "all"
      @page = normalize_page(page)
      @query = query
      @ecosystem = ecosystem || "all"
      @label_ids = label_ids&.split(",") || []
      @severity = severity || "all"
      @campaign = campaign
      @campaign_review_state = campaign_review_state || "all"
    end

    def advisory_reviews
      return @advisory_reviews if defined? @advisory_reviews

      @advisory_reviews = AdvisoryReview
        .preload(:feed_entries, :advisory, :cve_review, :labels)
        .order(order_by(@sort_by) => @sort)
        .by_curation_state(@curation_state)
        .by_curator(@curator)
        .by_default_ecosystem(@ecosystem)
        .by_source(@source)
        .by_campaign(@campaign, @campaign_review_state)
        .by_label_ids(@label_ids)
        .by_severity(@severity)
        .search_identifiers(@query)
        .page(@page)
    end

    def curation_states
      CURATION_STATES
    end

    def curators
      AdvisoryDB::Config::ActiveCurators::CURATORS
    end

    def curator_label(curator)
      curators.find(proc { curator.titleize }) { |login| login == curator }
    end

    def sources
      AdvisoryReviews::SOURCES.keys
    end

    def source_label(source)
      AdvisoryReviews::SOURCES.dig(source, :label) || source&.titleize
    end

    def labels_label
      return "Any" if @label_ids.blank?

      @label_ids.map do |label_id|
        name = Label.find(label_id.to_i.abs).name
        name.prepend("-") if label_id.starts_with?("-")
        name
      end.join(",")
    end

    def order_by(field)
      if field == "severity"
        AdvisoryReview.severity_order_sql
      elsif field == "date"
        :review_requested_at
      end
    end
  end
end
