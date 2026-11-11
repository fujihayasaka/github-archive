# typed: true
# frozen_string_literal: true

module IssueTimelineHelper
  module TotalCountOptimizationHelper

    sig { params(viewer: T.nilable(User), arguments: T::Hash[Symbol, T.untyped]).returns(T.nilable(Integer)) }
    def best_effort_total_count_limit(viewer, arguments)
      return nil unless viewer&.feature_flag_enabled_or_raise?(:timeline_best_effort_count_optimization) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      total_count_limit = arguments.present? ? arguments[:total_count_limit] : nil
      if total_count_limit.nil? || arguments[:after].present? || arguments[:before].present? || arguments[:focus].present? || arguments[:focus_text].present?
        # If the total count limit is not present, or if it is not applicable, we return nil so the caller will fallback to the regular total count
        nil
      else
        total_count_limit
      end
    end

    sig { params(total_count_optimization_applicable: T.nilable(T::Boolean), first: T.nilable(Integer), num_issue_ids: Integer, total_count_limit: T.nilable(Integer)).returns(T.nilable(Integer)) }
    def number_of_placeholders_to_load(total_count_optimization_applicable, first, num_issue_ids, total_count_limit)
      if !total_count_optimization_applicable || first.nil? || num_issue_ids != 1
        # The optimization is not applicable, we return nil so the caller will load all placeholders
        return nil
      end

      # A non-nil total_count_limit means the user has requested the best effort total count
      return total_count_limit if total_count_limit
      # Load just the first placeholders
      first
    end

    module ResolverHelper
      include Platform::Resolvers::CurrentLookahead

      BEST_EFFORT_TOTAL_COUNT_LIMIT = 300

      sig {  params(viewer: T.nilable(User)).returns(T.nilable(Integer)) }
      def total_count_limit(viewer)
        return nil unless viewer&.feature_flag_enabled_or_raise?(:timeline_best_effort_count_optimization) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        best_effort_total_count = T.let(nil, T.untyped)
        with_safe_access_to_current_lookahead(nil) do |current_lookahead|
          if current_lookahead.arguments[:total_count_limit].present?
            # To use the best effort total count, we need to ensure that the caller supplied a total count limit and asked for the best effort total count
            best_effort_total_count = current_lookahead.arguments[:total_count_limit]
          end
        end

        if best_effort_total_count.is_a?(Integer) && best_effort_total_count > BEST_EFFORT_TOTAL_COUNT_LIMIT
          raise Platform::Errors::ArgumentError.new("Best effort total count limit must be less than or equal to #{BEST_EFFORT_TOTAL_COUNT_LIMIT}")
        end

        best_effort_total_count
      end

      sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
      def total_count_optimization_applicable(viewer)
        return false unless FeatureFlag.vexi.enabled_or_raise?(:timeline_no_count_optimization) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

        # TODO: Make this optimization work for requests with focus
        if with_any_focus?
          GitHub.dogstats.increment("issue_event.loader.total_count_optimization_applicable", tags: ["result:false", "reason:focus"])
          return false
        end

        if with_total_count? && !total_count_limit(viewer).present?
          GitHub.dogstats.increment("issue_event.loader.total_count_optimization_applicable", tags: ["result:false", "reason:total_count"])
          return false
        end

        if with_after?
          GitHub.dogstats.increment("issue_event.loader.total_count_optimization_applicable", tags: ["result:false", "reason:after"])
          return false
        end

        GitHub.dogstats.increment("issue_event.loader.total_count_optimization_applicable", tags: ["result:true"])
        true
      end

      sig { returns(T.nilable(T::Boolean)) }
      def with_any_focus?
        with_safe_access_to_current_lookahead(nil) do |current_lookahead|
          current_lookahead.arguments[:focus].present? || current_lookahead.arguments[:focus_text].present?
        end
      end

      def with_after?
        with_safe_access_to_current_lookahead(nil) do |current_lookahead|
          current_lookahead.arguments[:after].present?
        end
      end
    end
  end
end
