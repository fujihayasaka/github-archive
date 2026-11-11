# typed: true
# frozen_string_literal: true

module Repos
  module Advisories
    class AdvisoryListComponent < ApplicationComponent
      attr_reader :current_user, :initial_state, :page, :query, :repository

      PAGE_SIZE = 10
      LEGACY_ECOSYSTEM_STORAGE_VALUES = {
        # Dotcom still has legacy RepositoryAdvisory affected_products rows stored as PascalCase.
        # Keep search normalization lowercase, but match legacy storage while those rows exist.
        "rubygems" => "RubyGems",
      }.freeze

      # A hash of availability/default predicates by state.
      # is_available predicates are used to determine if a given state is valid for navigation purposes.
      # is_default predicates are used to determine if a given state should be the default state on page arrival.
      # The order of this hash establishes precedence.
      AVAILABILITY_BY_STATE = {
        "triage" => { is_available: -> (s) { s.show_triage? }, is_default: -> (s) { s.advisory_counts["triage"] > 0 } },
        "draft" => { is_available: -> (s) { s.collaboration_authorized? }, is_default: -> (s) { s.advisory_counts["open"] > 0 } },
        "published" => { is_available: -> (_s) { true }, is_default: -> (_s) { true } },
        "closed" => { is_available: -> (s) { s.collaboration_authorized? }, is_default: -> (_s) { true } },
      }

      renders_one :footer

      def initialize(current_user:, initial_state:, page:, repository:, query: nil)
        @current_user = current_user
        @initial_state = initial_state
        @page = page
        @query = query
        @repository = repository
      end

      memoize def state
        initial_state_available = false
        initial_desired_state = initial_state
        if initial_desired_state != nil
          if AVAILABILITY_BY_STATE[initial_desired_state] != nil
            initial_state_available = AVAILABILITY_BY_STATE[initial_desired_state][:is_available].call(self)
          end
        end

        return initial_state if initial_state_available

        AVAILABILITY_BY_STATE.find do |kvp|
          availability_predicates = kvp[1]
          availability_predicates[:is_available].call(self) && availability_predicates[:is_default].call(self)
        end[0] # [0] gets the state key
      end

      def single_available_navigation_state?
        !(show_closed? || show_draft? || show_triage?)
      end

      memoize def pagination_scope
        current_advisories.paginate(page: page, per_page: PAGE_SIZE)
      end

      memoize def advisories
        pagination_scope.to_a
      end

      def triage?
        state == "triage"
      end

      def draft?
        state == "draft"
      end

      def published?
        state == "published"
      end

      def closed?
        state == "closed"
      end

      def state_icon
        case state
        when "triage" then "inbox"
        when "draft" then "shield"
        when "closed" then "shield-x"
        when "published" then "shield-check"
        end
      end

      # Unfiltered counts used for tab availability/authorization checks.
      # Ensures tabs remain visible even when search filters narrow results.
      memoize def advisory_counts
        {
          "open" => available_advisories_for_state.open_triaged.count,
          "triage" => available_advisories_for_state.open_untriaged.count,
          "closed" => available_advisories_for_state.closed.count,
          "published" => available_advisories_for_state.published.count,
        }
      end

      # Filtered counts reflect the current search query.
      # Used for displaying tab totals to match the visible advisory list.
      memoize def filtered_advisory_counts
        {
          "open" => available_advisories.open_triaged.count,
          "triage" => available_advisories.open_untriaged.count,
          "closed" => available_advisories.closed.count,
          "published" => available_advisories.published.count,
        }
      end

      memoize def total_triage_count
        filtered_advisory_counts.fetch("triage", 0)
      end

      memoize def total_draft_count
        filtered_advisory_counts.fetch("open", 0)
      end

      memoize def total_published_count
        filtered_advisory_counts.fetch("published", 0)
      end

      memoize def total_closed_count
        filtered_advisory_counts.fetch("closed", 0)
      end

      memoize def advisory_management_authorized?
        repository.advisory_management_authorized_for?(current_user)
      end

      memoize def collaboration_authorized?
        advisory_management_authorized? ||
            advisory_counts.fetch("open", 0) > 0 ||
            advisory_counts.fetch("closed", 0) > 0
      end

      alias_method :show_draft?, :collaboration_authorized?
      alias_method :show_closed?, :collaboration_authorized?

      memoize def pvd_repo_authorized?
        AdvisoryDB::Pvd.authorized_repo?(repo: repository)
      end

      memoize def show_triage?
        pvd_repo_authorized? &&
          (
            advisory_management_authorized? ||
              available_advisories_for_state.preload(:author).open_untriaged.any? do |aa|
                aa.readable_by?(current_user)
              end
          )
      end

      def advisory_has_unread_notifications?(advisory)
        return false unless current_user

        @unread_advisory_ids ||= GitHub.newsies.web.all(current_user, { unread: true, thread_types: ["RepositoryAdvisory"] }).inject(Set.new) do |ids, newsie|
          ids << newsie.dig(:thread, :id).to_i
          ids
        end

        @unread_advisory_ids.include?(advisory.id)
      end

      private

      def current_advisories
        if published?
          available_advisories.state(state.to_sym).preload(:publisher)
        else
          available_advisories.state(state.to_sym).preload(:author)
        end
      end

      memoize def available_advisories
        scope = available_advisories_for_state
        scope = apply_search_filters(scope)
        scope
      end

      memoize def available_advisories_for_state
        repository.repository_advisories.
          available_to(current_user).
          limit_advisory_type.
          newest_first
      end

      memoize def parsed_query
        Search::Queries::SecurityCenter::RepositoryAdvisoriesQuery.parse_and_normalize(query)
      end

      def apply_search_filters(scope)
        return scope if query.blank?

        filters = parsed_query

        if filters[:severity].present?
          scope = scope.where(severity: filters[:severity])
        end

        if filters[:phrase].present?
          scope = scope.search_by_query(filters[:phrase])
        end

        if filters[:ecosystem].present?
          ecosystem_values = filters[:ecosystem].flat_map do |ecosystem|
            [ecosystem, LEGACY_ECOSYSTEM_STORAGE_VALUES[ecosystem]]
          end.compact.uniq

          scope = scope.left_outer_joins(:affected_products)
            .where(repository_advisory_affected_products: { ecosystem: ecosystem_values })
            .distinct
        end

        if filters[:package].present?
          sanitized_packages = filters[:package].map { |p| "%#{ActiveRecord::Base.sanitize_sql_like(p.downcase)}%" }
          scope = scope.left_outer_joins(:affected_products)
            .where(sanitized_packages.map { "CONVERT(repository_advisory_affected_products.package USING utf8mb4) LIKE ?" }.join(" OR "), *sanitized_packages)
            .distinct
        end

        if filters[:sort].present?
          scope = case filters[:sort]
          when :oldest
            scope.reorder(id: :asc)
          when :severity
            # Safe use of Arel.sql — no user input; values are hardcoded.
            scope.reorder(Arel.sql("FIELD(severity, 3, 2, 1, 0, NULL) ASC, id DESC"))
          else
            scope
          end
        end

        scope
      end
    end
  end
end
