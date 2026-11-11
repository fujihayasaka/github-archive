# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class MemberRequestsComponent < ApplicationComponent
      sig { params(entity: T.any(::Business, ::Organization), feature: MemberFeatureRequest::Feature).void }
      def initialize(entity:, feature:)
        @entity = entity
        @feature = feature
        @is_business = T.let(entity.is_a?(::Business), T::Boolean)
      end

      sig { returns(Integer) }
      def requests_count
        if is_business
          MemberFeatureRequest.admin_requests
            .where(billing_entity_id: T.cast(entity, ::Business).id, feature: feature)
            .requested
            .count
        else
          MemberFeatureRequest.total_for_feature(T.cast(entity, ::Organization), feature)
        end
      end

      sig { returns(T::Array[::User]) }
      def requesting_users
        scope = if is_business
          MemberFeatureRequest.admin_requests
            .where(billing_entity_id: T.cast(entity, ::Business).id, feature: feature)
            .requested
        else
          MemberFeatureRequest.requested_member_requests(T.cast(entity, ::Organization))
            .where(feature: feature)
        end

        scope.includes(:requester)
            .order(created_at: :desc)
            .limit(5)
            .map(&:requester)
            .compact
      end

      sig { returns(T::Boolean) }
      def render?
        return false if MemberFeatureRequest.unavailable?
        return false if requests_count.zero?
        if is_business
          !feature.supported?(business: T.cast(entity, ::Business))
        else
          !feature.supported?(request_entity: T.cast(entity, ::Organization))
        end
      end

      sig { returns(String) }
      def formatted_count_text
        count = requests_count
        requester_type = is_business ? "admin" : "member"
        if count == 1
          "<strong>1 #{requester_type}</strong> requested #{feature.name}".html_safe # rubocop:disable Rails/OutputSafety
        else
          "<strong>#{count} #{requester_type.pluralize}</strong> requested #{feature.name}".html_safe # rubocop:disable Rails/OutputSafety
        end
      end

      # Cross-link the per-policy count to the aggregated enterprise
      # "Requests from members" settings page when that surface is enabled.
      sig { returns(T::Boolean) }
      def show_enterprise_member_requests_link?
        is_business && T.cast(entity, ::Business).feature_flag_enabled?(:enterprise_member_requests, default: false)
      end

      sig { returns(String) }
      def enterprise_member_requests_path
        settings_member_requests_enterprise_path(T.cast(entity, ::Business))
      end

      private

      sig { returns(T.any(::Business, ::Organization)) }
      attr_reader :entity

      sig { returns(MemberFeatureRequest::Feature) }
      attr_reader :feature

      sig { returns(T::Boolean) }
      attr_reader :is_business
    end
  end
end
