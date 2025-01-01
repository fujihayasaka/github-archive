# typed: true
# frozen_string_literal: true

module CommandPalette
  class ApplicationProvider
    include UrlHelpers
    include ConditionalAccessHelper

    class << self
      def factory_identifier
        return @factory_identifier if defined?(@factory_identifier)
        @factory_identifier = T.must(name).underscore.split("/").last.gsub("_provider", "").to_sym
      end

      def fetch_modes
        modes.map do |mode|
          Modes.mode(mode)
        end
      end

      def supported_modes
        fetch_modes.map(&:character)
      end

      def supported_scope_types
        fetch_modes.flat_map(&:scope_types).uniq
      end

      def type
        "remote"
      end

      def remote_src?
        true
      end

      def debounce
        200
      end

      def enabled?(context)
        true
      end

      def has_commands?
        false
      end

      private

      def modes
        [:default]
      end
    end

    delegate :current_user, :scope, :cap_filter, :return_to, :subject, to: :context
    attr_reader :context

    def initialize(context)
      @context = context
    end

    def search(query)
      raise NotImplementedError, "Please implement the method `##{__method__}` on your provider to return a List<Result>"
    end

    def filter_results(results)
      # only need to check access policies in unscoped searches
      # which prevents being able to scope into blocked orgs/repos
      return results unless cap_filterable_results?

      results_by_targets = results.group_by { |r| r.object&.target_for_conditional_access }
      filtered_by_unauthorized_policies(results_by_targets)
    end

    def filtered_by_unauthorized_policies(results_by_targets)
      unauthorized_policies = cap_filter.unauthorized(results_by_targets.keys.flatten.compact)

      results_by_targets.each do |target, _results|
        next unless target.present?

        unmet_policies_for_target = unauthorized_policies[target]
        next unless unmet_policies_for_target

        # Replace restricted resuls with access policy results
        results_by_targets[target] = unmet_policies_for_target.policies.keys.map do |policy|
          Result.access_policy(policy, target, return_to)
        end
      end.values.flatten
    end

    def cap_filterable_results?
      cap_filter.present?
    end

    # Return true when query's `is` values are within the allowed values.
    def query_matches_allowed_types?(*allowed_types, query:, filter: :is)
      query_types = Search::ParsedQuery.parse(query, terms: [filter]).each_with_object([]) do |query_chunk, types|
        if query_chunk[0] == filter && query_chunk[1].present?
          types << query_chunk[1]
        end
      end

      return true if query_types.blank?

      # True when every query type is in allowed_types
      disallowed_types = query_types - allowed_types

      disallowed_types.empty?
    end

    private

    # Allows the url helpers to work within providers
    def default_url_options
      { host: GitHub.host_name }
    end

    def scope_matches?
      self.class.supported_scope_types.empty? ||
        (self.class.supported_scope_types.include?("") && scope.blank?) ||
        self.class.supported_scope_types.include?(ResultScope::CLASS_TO_TYPE[scope.type.name])
    end
  end
end
