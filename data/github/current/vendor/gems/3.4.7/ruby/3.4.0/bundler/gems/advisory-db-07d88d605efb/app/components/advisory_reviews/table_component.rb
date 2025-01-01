# frozen_string_literal: true

module AdvisoryReviews
  class TableComponent < ApplicationComponent
    include HasSorting
    include HasLabelFiltering
    include HasCurationState
    include HasSeverities

    attr_reader :advisory_reviews, :sort, :sort_by

    def initialize(advisory_reviews:, sort: nil, sort_by: nil)
      @advisory_reviews = advisory_reviews
      @sort = sort
      @sort_by = sort_by
    end

    def sorting_enabled?
      sort.present? || sort_by.present?
    end

    def cve_link(advisory_review)
      cve_review = advisory_review.cve_review

      if cve_review
        render(Primer::Beta::Link.new(href: cve_review_path(cve_review), muted: true, font_weight: :bold)) do
          if cve_review.assigned_cve_id
            cve_review.assigned_cve_id
          elsif cve_review.open?
            "Open"
          else
            "Closed"
          end
        end
      else
        advisory_review.cve_id
      end
    end

    def source_icons(advisory_review)
      sources = advisory_review
        .feed_entries
        .map(&:source)
        .uniq
        .sort

      if sources.empty?
        sources << "unknown"
      end

      sources.map { |source| AdvisoryReviews::SourceIconComponent.new(source: source) }
    end

    def ecosystems_with_package_names(advisory_review)
      vulnerabilities = advisory_review.vulnerabilities.values
      string_ecosystem_and_package_name = vulnerabilities.map do |v|
        ecosystem = v["ecosystem"]
        package_name = v["package_name"]
        next "#{ecosystem}:#{package_name}" if ecosystem.present? && package_name.present?
        next ecosystem if ecosystem.present?

        next
      end.uniq.compact
      string_ecosystem_and_package_name.join(", ")
    end
  end
end
