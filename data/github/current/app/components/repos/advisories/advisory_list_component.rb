# typed: true
# frozen_string_literal: true

module Repos
  module Advisories
    class AdvisoryListComponent < ApplicationComponent
      attr_reader :current_user, :initial_state, :page, :repository

      PAGE_SIZE = 10

      # A hash of availability/default predicates by state.
      # is_available predicates are used to determine if a given state is valid for navigation purposes.
      # is_default predicates are used to determine if a given state should be the default state on page arrival.
      # The order of this hash establishes precedence.
      AVAILABILITY_BY_STATE = {
        "triage" => { is_available: -> (s) { s.show_triage? }, is_default: -> (s) { s.advisory_counts["triage"] > 0 }  },
        "draft" => { is_available: -> (s) { s.collaboration_authorized? }, is_default: -> (s) { s.advisory_counts["open"] > 0 }  },
        "published" => { is_available: -> (_s) { true }, is_default: -> (_s) { true } },
        "closed" => { is_available: -> (s) { s.collaboration_authorized? }, is_default: -> (_s) { true } },
      }

      renders_one :footer

      def initialize(current_user:, initial_state:, page:, repository:)
        @current_user = current_user
        @initial_state = initial_state
        @page = page
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

      memoize def advisory_counts
        {
          "open" => available_advisories.open_triaged.count,
          "triage" => available_advisories.open_untriaged.count,
          "closed" => available_advisories.closed.count,
          "published" => available_advisories.published.count,
        }
      end

      memoize def total_triage_count
        advisory_counts.fetch("triage", 0)
      end

      memoize def total_draft_count
        advisory_counts.fetch("open", 0)
      end

      memoize def total_published_count
        advisory_counts.fetch("published", 0)
      end

      memoize def total_closed_count
        advisory_counts.fetch("closed", 0)
      end

      memoize def advisory_management_authorized?
        repository.advisory_management_authorized_for?(current_user)
      end

      memoize def collaboration_authorized?
        advisory_management_authorized? ||
          total_draft_count > 0 ||
          total_closed_count > 0
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
              available_advisories.preload(:author).open_untriaged.any? do |aa|
                aa.readable_by?(current_user)
              end
          )
      end

      def advisory_has_unread_notifications?(advisory)
        return false unless current_user # rubocop:disable GitHub/CurrentUserNilCheck

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
        repository.repository_advisories.
          available_to(current_user).
          limit_advisory_type.
          newest_first
      end
    end
  end
end
