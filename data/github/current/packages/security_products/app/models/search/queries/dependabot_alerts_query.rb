# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class DependabotAlertsQuery < Search::Queries::VulnerabilityQuery
      include GitHub::DatadogHelper
      include GitHub::Memoizer

      def self.field_list
        [:user, :is, :sort].freeze
      end

      def self.unique_field_list
        [:sort].freeze
      end

      REPOSITORY_TYPES = %w[public private internal].freeze
      REPO_BATCH_SIZE = 1000
      MAX_REPO_IDS = 31_000
      DATADOG_PREFIX = "search_queries_dependabot_alerts_query"

      attr_reader :org_ids_to_exclude, :repo_limit_exceeded

      def initialize(query:, org_ids_to_exclude: nil, current_user: nil)
        super({ raw_phrase: query })

        @org_ids_to_exclude = org_ids_to_exclude || []
        @current_user = current_user
        @repo_limit_exceeded = false
      end

      def closed?
        qualifier_selected?(name: :is, value: "closed")
      end

      def replace_state(closed:)
        new_query = parsed_query.dup
        if closed != closed?
          if closed
            new_query << [:is, "closed"]
          else
            new_query.reject! { |component| matches_qualifier?(component, :is, "closed") }
          end
        end
        self.class.stringify(new_query).presence
      end

      def repository_type
        return @repository_type if defined? @repository_type

        @repository_type = qualifier_values(name: :is).find do |value|
          value.in?(REPOSITORY_TYPES)
        end
      end

      def toggle_repository_type(value:)
        selected = qualifier_selected?(name: :is, value: value)
        new_query = parsed_query.dup
        new_query.reject! do |component|
          REPOSITORY_TYPES.any? { |type| matches_qualifier?(component, :is, type) }
        end
        new_query << [:is, value] if value.present? && !selected
        self.class.stringify(new_query).presence
      end

      def repository_ids
        return [] if invalid_owners?
        return [] unless current_user.present?
        return @repository_ids if defined? @repository_ids

        authorized_repo_ids =
          datadog_distribution_time(:enumerate_authorized_repo_ids, tags: ["ff_enabled:#{current_user.feature_flag_enabled?(:dependabot_alerts_authorized_repo_query, default: false)}"]) do
            enumerate_authorized_repo_ids
          end

        if authorized_repo_ids.length > MAX_REPO_IDS
          authorized_repo_ids = authorized_repo_ids.sort.take(MAX_REPO_IDS)
          @repo_limit_exceeded = true
        end

        active_authorized_repo_ids =
          authorized_repo_ids.each_slice(REPO_BATCH_SIZE).flat_map do |repo_ids|
            Repository.where(id: repo_ids).with_vulnerability_alerts_enabled.ids
          end

        if active_authorized_repo_ids.present? & filter_repository_ids?
          scope = Repository.where(id: active_authorized_repo_ids)

          if owner_ids.present?
            scope = scope.where(owner_id: owner_ids - org_ids_to_exclude)
          elsif org_ids_to_exclude.present?
            scope = scope.where.not(organization_id: org_ids_to_exclude)
          end

          if repository_name.present?
            scope = scope.with_substring("name", repository_name)
          end

          scope = filter_repository_type(scope)

          active_authorized_repo_ids = scope.pluck(:id)
        end

        GitHub.dogstats.distribution("dependabot_alerts_query.repository_ids", active_authorized_repo_ids.size, tags: ["filtered:#{filter_repository_ids?}"])

        @repository_ids = active_authorized_repo_ids
      end

      def enumerate_authorized_repo_ids
        if !current_user.feature_flag_enabled?(:dependabot_alerts_authorized_repo_query, default: false) || !owners.present?
          return SecurityProduct::AuthorizationEnumerator.for_dependabot(current_user).authorized_repository_ids
        end

        repo_ids = T.let([], T::Array[T.untyped])

        orgs = owners.select { |u| u.id != current_user.id }
        orgs.each do |org|
          enumerator = SecurityProduct::AuthorizationEnumerator.new(user: current_user, actions: [:view_dependabot_alerts], options: { organization: org })
          repo_ids += enumerator.authorized_repository_ids
        end

        if owners.map(&:id).include?(current_user.id)
          repo_ids += Repository.where(owner_id: current_user.id).pluck(:id)
        end

        repo_ids
      end

      def apply_sort(scope)
        direction = if qualifier_selected?(name: :sort, value: "created-asc")
          :asc
        else
          :desc
        end
        scope.order(created_at: direction)
      end

      memoize def owners
        return [] unless owner_logins.present?

        scope = User.where(login: owner_logins)
        scope.where.not(id: org_ids_to_exclude) if org_ids_to_exclude.present?

        scope.to_a
      end

      def owner_ids
        @owner_ids ||= User.where(login: owner_logins).pluck(:id) if owner_logins.present?
      end

      private

      def filter_repository_type(scope)
        case repository_type
        when "public"
          scope.public_scope
        when "private"
          scope.private_scope
        when "internal"
          scope.internal_scope
        else
          scope
        end
      end

      def filter_repository_ids?
        owner_ids.present? || org_ids_to_exclude.present? || repository_name.present? || repository_type.present?
      end

      def repository_name
        return @repository_name if defined? @repository_name

        @repository_name = parsed_query.find { |component| component.is_a?(String) }
      end

      def owner_logins
        @owner_logins ||= qualifier_values(name: :user).map(&:downcase).uniq
      end

      def invalid_owners?
        owner_logins.present? && owner_logins.size != owner_ids.size
      end
    end
  end
end
