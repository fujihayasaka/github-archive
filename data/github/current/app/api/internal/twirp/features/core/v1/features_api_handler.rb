# typed: true
# frozen_string_literal: true

require "monolith-twirp-features-core"

module Api::Internal::Twirp::Features
  module Core
    module V1
      # Handler for the MonolithTwirp::Features::Core::V1::FeaturesAPIService
      class FeaturesAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Features::Core::V1::FeaturesAPIService

        # Explicitly set as exempt from the tenant context requirement because this API handler deals with
        # feature flags and actors that are on global tables, accessible to all tenants and not tenant scoped.
        exempt_from_tenant_context_requirement(
          only: %i[
            check_actor_feature
            check_actors_feature
            check_global_feature
            check_actor_features
          ]
        )

        METRIC_NAME = "twirp.features_api_handler"

        allow_access_for :client, allowed_clients: %w[
          actions_broker_listener
          actions_broker_worker
          actions_results
          actions_run_service
          actions_runner_admin
          advisory_db
          billing
          chat_integrations
          conduit
          copilot_api
          copilot_abuse_service
          copilot_activity_service
          copilot_usage_service
          dependabot_api
          dependency_graph_api
          dependency_graph_platform
          dependency_snapshots_api
          driftwood
          git_src_migrator
          gitbackups
          goproxy
          hookshot_go
          hosted_compute_gps_lab
          hosted_compute_gps_load
          hosted_compute_gps_internal
          hosted_compute_gps_production
          hosted_compute_gps_ado
          hosted_compute_gps_prod_eus_01
          hosted_compute_gps_prod_ae_01
          hosted_compute_gps_prod_sdc_01
          hosted_compute_gps_prod_weu_01
          hosted_compute_ims
          insights
          issues_graph
          kredz
          launch
          licensing
          notifyd
          npm_registry
          octoshift
          orca
          package_registry
          pages_deployer
          pages_router
          spokesd
          token_scanning_service
          turboghas
          turboscan
          vigilance
        ].freeze

        def before_rpc(rack_env, env)
          case env[:rpc_method]
          when :CheckActorFeature
            require_arguments(env, [:feature, :actor_id])
          when :CheckActorsFeature
            require_arguments(env, [:feature, :actor_ids])
          when :CheckGlobalFeature
            require_arguments(env, [:feature])
          when :CheckActorFeatures
            require_arguments(env, [:features, :actor_id])
          end
        end

        # Public: Implementation of the CheckActorFeature Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::Core::V1::CheckActorFeatureRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::Core::V1::CheckActorFeatureResponse, or a Twirp::Error.
        def check_actor_feature(req, env)
          actor = actor_from_actor_id(req.actor_id)
          GitHub.dogstats.increment(METRIC_NAME, tags: ["feature:#{req.feature}"])
          result_for_actor_id(req.actor_id, actor, req.feature)
        end

        # Public: Implementation of the CheckActorsFeature Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::Core::V1::CheckActorsFeatureRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::Core::V1::CheckActorsFeatureResponse, or a Twirp::Error.
        def check_actors_feature(req, env)
          GitHub.dogstats.increment(METRIC_NAME, tags: ["feature:#{req.feature}"])
          results = actor_ids_by_class(req.actor_ids).flat_map do |actor_class, actor_ids|
            actors = actors_for_actor_class(actor_class, actor_ids)
            actor_ids.map do |actor_id|
              actor = actors[actor_id]
              result_for_actor_id(actor_id, actor, req.feature)
            end
          end

          results.sort_by! { |result| req.actor_ids.index(result[:actor_id]) }

          { results: results }
        end

        # Public: Implementation of the CheckGlobalFeature Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::Core::V1::CheckGlobalFeatureRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::Core::V1::CheckGlobalFeatureResponse, or a Twirp::Error.
        def check_global_feature(req, env)
          GitHub.dogstats.increment(METRIC_NAME, tags: ["feature:#{req.feature}"])
          { is_enabled: GitHub.flipper[req.feature].enabled? }
        end

        # Public: Implementation of the CheckActorFeatures Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::Core::V1::CheckActorFeaturesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::Core::V1::CheckActorFeaturesResponse, or a Twirp::Error.
        def check_actor_features(req, env)
          actor = actor_from_actor_id(req.actor_id)
          if actor.nil?
            # Note that we emit a statistic here to be consistent with the single feature
            # fetch behaviour. Additionally, we emit a `actor:nil` tag for better observability.
            req.features.each do |feature_name|
              GitHub.dogstats.increment(METRIC_NAME, tags: ["feature:#{feature_name}", "actor:nil"])
            end

            return {
              actor_id: req.actor_id,
              feature_flags: req.features.to_h { |feature_name| [feature_name, false] }
            }
          end

          FeatureFlag.vexi.preload(req.features, fetch_directly_from_adapter: false, instrumentation_properties: {
            "code.namespace": self.class.name&.underscore,
          })

          feature_flags = req.features.to_h do |feature_name|
            GitHub.dogstats.increment(METRIC_NAME, tags: ["feature:#{feature_name}"])
            [feature_name, actor.feature_enabled?(feature_name.to_sym)]
          end

          { actor_id: req.actor_id, feature_flags: feature_flags }
        end

        private

        def actor_from_actor_id(actor_id)
          GitHub::FlipperActor.from_flipper_id(actor_id)
        rescue ArgumentError, NameError
          # The actor_id is invalid
          #   ArgumentError: doesn't contain a `:` separator. e.g. User1234 instead of User:1234
          #   NameError: class_name is not a valid class. e.g. FakeClass:1234 instead of User:1234
          nil
        end

        def actor_class_from_actor_id(actor_id)
          class_name = GitHub::FlipperActor.class_name_from_flipper_id(actor_id)
          class_name.constantize
        rescue ArgumentError, NameError
          # The actor_id is invalid
          #   ArgumentError: doesn't contain a `:` separator. e.g. User1234 instead of User:1234
          #   NameError: class_name is not a valid class. e.g. FakeClass:1234 instead of User:1234
          nil
        end

        def actor_ids_by_class(actor_ids)
          actor_ids.to_a.each_with_object({}) do |actor_id, hash|
            actor_class = actor_class_from_actor_id(actor_id)
            hash[actor_class] ||= []
            hash[actor_class] << actor_id
          end
        end

        def actors_for_actor_class(actor_class, actor_ids)
          return {} unless actor_class

          if actor_class < ActiveRecord::Base
            ids = actor_ids.map { |actor_id| GitHub::FlipperActor.flipper_id_to_parts(actor_id).last }
            actor_class.where(id: ids).to_a.index_by(&:flipper_id)
          else
            actor_ids.each_with_object({}) do |actor_id, hash|
              hash[actor_id] = actor_from_actor_id(actor_id)
            end
          end
        end

        def result_for_actor_id(actor_id, actor, feature_name)
          enabled = actor ? actor.feature_enabled?(feature_name.to_sym) : false

          { actor_id: actor_id, is_enabled: enabled }
        end

        def require_arguments(env, arguments)
          arguments.each do |argument|
            next if env[:input].public_send(argument).present?
            return Twirp::Error.invalid_argument("must be provided", argument: argument.to_s)
          end

          nil
        end
      end
    end
  end
end
