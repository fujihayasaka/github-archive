# typed: true
# frozen_string_literal: true

require "monolith-twirp-insights-core"

module Api::Internal::Twirp::Insights
  module Core
    module V1
      # Handler for the MonolithTwirp::Insights::Core::V1::FeatureFlagAPIService
      class FeatureFlagAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["insights"]
        handles_service MonolithTwirp::Insights::Core::V1::FeatureFlagAPIService

        ALLOWED_FEATURE_FLAGS = %w[
          memex_insights
          insights_enabled
          insights_enabled_staging
          security_center_ghas_insights
          actions_insights_enabled
          ospo_insights_enabled
        ]

        # Insights in Memex is a gated feature to be enabled only for orgs with specific paid plans.
        MEMEX_INSIGHTS_FEATURES = [
          :projectsv2_insights_limited,
          :projectsv2_insights_basic
        ]

        # Public: Implementation of the EnableFeatureFlag Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::EnableFeatureFlagRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::EnableFeatureFlagResponse, or a Twirp::Error.
        def enable_feature_flag(req, env)
          return Twirp::Error.invalid_argument("should be non-empty", argument: "org_ids") if req.org_ids.empty?
          return Twirp::Error.invalid_argument("not a valid feature flag for insights", argument: "feature_name") unless ALLOWED_FEATURE_FLAGS.include?(req.feature_name)

          ActiveRecord::Base.connected_to(role: :writing) do
            orgs = Organization.where(id: req.org_ids.to_a)

            if orgs.length == 0
              return Twirp::Error.not_found("requested organizations not found")
            end

            feature_flag = req.feature_name.to_sym

            response = orgs.map do |org|
              is_enabled = begin
                if skip_memex_feature_flag?(feature_flag, org)
                  false
                else
                  GitHub.flipper[feature_flag].enable(org)
                  true
                end
              rescue Flipper::Error, Memcached::Error, ActiveRecord::ActiveRecordError => e
                Failbot.report(e, org_id: org.id)
                GitHub.flipper[feature_flag].enabled?(org)
              end

              { org_id: org.id, is_enabled: is_enabled }
            end

            return { organizations: response }
          end
        end

        # Public: Implementation of the DisableFeatureFlag Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::DisableFeatureFlagRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::EnableFeatureFlagResponse, or a Twirp::Error.
        def disable_feature_flag(req, env)
          return Twirp::Error.invalid_argument("should be non-empty", argument: "org_ids") if req.org_ids.empty?
          return Twirp::Error.invalid_argument("not a valid feature flag for insights", argument: "feature_name") unless ALLOWED_FEATURE_FLAGS.include?(req.feature_name)

          ActiveRecord::Base.connected_to(role: :writing) do
            orgs = Organization.where(id: req.org_ids.to_a)

            if orgs.length == 0
              return Twirp::Error.not_found("requested organizations not found")
            end

            feature_flag = req.feature_name.to_sym

            response = orgs.map do |org|
              is_enabled = begin
               GitHub.flipper[feature_flag].disable(org)
               false
             rescue Flipper::Error, Memcached::Error, ActiveRecord::ActiveRecordError => e
               Failbot.report(e, org_id: org.id)
               GitHub.flipper[feature_flag].enabled?(org)
             end

              { org_id: org.id, is_enabled: is_enabled }
            end

            return { organizations: response }
          end
        end

        # Public: Implementation of the GetFeatureFlags Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Insights::Core::V1::GetFeatureFlagsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Insights::Core::V1::GetFeatureFlagsResponse, or a Twirp::Error.
        def get_feature_flags(req, env)
          return Twirp::Error.invalid_argument("should be non-empty", argument: "org_id") if req.org_id == 0
          return Twirp::Error.invalid_argument("not a valid feature flag for insights", argument: "flags") if (req.flags - ALLOWED_FEATURE_FLAGS).count > 0

          ActiveRecord::Base.connected_to(role: :reading) do
            orgs = Organization.where(id: req.org_id)
            if orgs.length == 0
              return Twirp::Error.not_found("requested organization not found")
            end

            org = orgs.first

            response = req.flags.map do |flag|
              { name: flag, is_enabled: GitHub.flipper[flag].enabled?(org) }
            end

            return { org_id: req.org_id, flags: response }
          end
        end

        #
        # feature_flag - The feature flag symbol to check for Memex applicability.
        # organization - The organization instance to check for feature gating against its plan.
        private def skip_memex_feature_flag?(feature_flag, organization)
          feature_flag == :memex_insights && MEMEX_INSIGHTS_FEATURES.none? { |feature| organization.plan_supports?(feature) }
        end

      end
    end
  end
end
