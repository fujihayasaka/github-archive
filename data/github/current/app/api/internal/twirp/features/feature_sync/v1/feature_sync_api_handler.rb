# typed: true
# frozen_string_literal: true

require "monolith-twirp-features-featuresync"

module Api::Internal::Twirp::Features
  module FeatureSync
    module V1
      # Handler for the MonolithTwirp::Features::FeatureSync::V1::FeatureSyncAPIService
      class FeatureSyncAPIHandler < Api::Internal::Twirp::Handler
        extend T::Sig
        allow_access_for :client, allowed_clients: ["feature_flag_hub"]
        handles_service MonolithTwirp::Features::FeatureSync::V1::FeatureSyncAPIService

        # Explicitly set as exempt from the tenant context requirement because this API handler deals with
        # feature flags and actors that are on global tables, accessible to all tenants and not tenant scoped.
        exempt_from_tenant_context_requirement(
          only: %i[
            synchronize_feature
            synchronize_actors
          ]
        )

        ACTOR_LIMIT = 100

        def before_rpc(rack_env, env)
          # Both endpoints must have a feature name to work
          require_arguments(env, [:name])
        end

        # Public: Implementation of the SynchronizeFeature Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::FeatureSync::V1::SynchronizeFeatureRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::FeatureSync::V1::SynchronizeFeatureResponse, or a Twirp::Error.
        sig { params(req: MonolithTwirp::Features::FeatureSync::V1::SynchronizeFeatureRequest, env: T.untyped).returns(T.any(MonolithTwirp::Features::FeatureSync::V1::SynchronizeFeatureResponse, Twirp::Error)) }
        def synchronize_feature(req, env)
          existing = T.let(nil, T.nilable(FlipperFeature))

          GitHub.logger.info("synchronize_feature starting FlipperFeature.find_by", "feature_flag.key" => req.name)

          ActiveRecord::Base.connected_to(role: :writing) do
            existing = FlipperFeature.find_by(name: req.name)
          end

          GitHub.logger.info("synchronize_feature finished FlipperFeature.find_by", "feature_flag.key" => req.name)

          # If the feature to sync is deleted, delete it from the database
          if existing && req.is_deleted
            GitHub.logger.info("synchronize_feature starting delete feature", "feature_flag.key" => req.name)
            ActiveRecord::Base.connected_to(role: :writing) do
              ::FlipperFeature.transaction do
                if existing.delete
                  binds = {
                    id: existing.id,
                  }
                  ApplicationRecord::Domain::Features.connection.delete(Arel.sql(<<-SQL, **binds))
                    DELETE flipper_gates
                    FROM flipper_gates
                    WHERE flipper_gates.flipper_feature_id = :id
                  SQL
                end
              end
              return MonolithTwirp::Features::FeatureSync::V1::SynchronizeFeatureResponse.new
            end
            GitHub.logger.info("synchronize_feature finished delete feature", "feature_flag.key" => req.name)

            return Twirp::Error.internal(existing.errors.full_messages.join(", "))
          end

          # If the feature to sync is deleted and doesn't exist in the database, no action required
          if req.is_deleted
            return MonolithTwirp::Features::FeatureSync::V1::SynchronizeFeatureResponse.new
          end

          # Create/Update feature's basic properties
          # Created date will be stamped by the database and not the created date on the ffh.
          # In most cases, the offset would be off by a couple of seconds.
          params = {
            name: req.name,
            description: req.description,
            service_name:  req.service_name,
            github_org_team_id: req.owning_team_id.empty? ? nil : req.owning_team_id.to_i,
            slack_channel: req.slack_channel,
            long_lived: req.long_lived,
            tracking_issue_url: req.tracking_url,
            stale_at: req.stale_at.nil? ? nil : Time.at(req.stale_at&.seconds, req.stale_at&.nanos, :nsec),
            exclusion_rule: 1,
          }

          if !existing
            params[:rollout_tree] = 1 # dotcom_and_proxima
          end

          # Depending on if the feature exists, we'll either create a new FlipperFeature to store it in `feature` variable
          # or we'll update the existing one (not persisted yet) and store the updated feature in `feature` variable to be persisted later
          existing.assign_attributes(params) if existing
          feature = existing ? existing : FlipperFeature.new(params)

          ActiveRecord::Base.connected_to(role: :writing) do
            begin
              GitHub.logger.info("synchronize_feature starting saving feature", "feature_flag.key" => req.name)

              feature.save!
              GitHub.logger.info("synchronize_feature finished saving feature", "feature_flag.key" => req.name)
            rescue ActiveRecord::RecordInvalid => _
              return Twirp::Error.invalid_argument(feature.errors.full_messages.join(", "), arguments: feature.errors.attribute_names.join(", "))
            end

            # NOTE: We need to make sure not to use the Flipper::Feature methods (see delegated methods in flipper_feature.rb)
            # as they'll use the adapters which will eventually trigger a sync back to the feature-flag-hub
            # sync boolean gates
            if req.is_boolean_gate_defined
              GitHub.logger.info("synchronize_feature starting mysql transaction", "feature_flag.key" => req.name)
              ::FlipperFeature.transaction do
                binds = {
                  name: req.name,
                }
                ApplicationRecord::Domain::Features.connection.delete(Arel.sql(<<-SQL, **binds))
                  DELETE flipper_gates
                  FROM flipper_gates
                  INNER JOIN flipper_features ON flipper_features.id = flipper_gates.flipper_feature_id
                  WHERE flipper_features.name = :name
                SQL
                if req.is_boolean_gate_enabled
                  new_boolean_gate = FlipperGate.create(
                    flipper_feature_id: feature.id,
                    name: "boolean",
                    value: true
                  )
                  new_boolean_gate.save!
                end
              end
              GitHub.logger.info("synchronize_feature finished mysql transaction", "feature_flag.key" => req.name)
            else
              # sync percentage_of_actors and percentage_of_time gates
              apply_percentage(feature, "percentage_of_actors", req.is_percentage_actor_gate_defined, req.percentage_actor_value)
              apply_percentage(feature, "percentage_of_time", req.is_percentage_time_gate_defined, req.percentage_time_value)

              # sync groups gate
              sync_group_gates(feature, req.is_custom_group_gate_defined, req.custom_group_value)
            end
            payload = {
              feature_name: feature.name,
              operation: "synchronize_feature",
              state: {
                enabled: req.is_boolean_gate_enabled,
                percentage_actors: req.percentage_actor_value,
                percentage_time: req.percentage_time_value,
                custom_gates: req.custom_group_value,
              },
            }
            GitHub.instrument "feature.synchronize_feature", payload
            feature.update(rollout_updated_at: Time.now.utc)
          end

          MonolithTwirp::Features::FeatureSync::V1::SynchronizeFeatureResponse.new
        end

        # Public: Implementation of the SynchronizeActors Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Features::FeatureSync::V1::SynchronizeActorsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Features::FeatureSync::V1::SynchronizeActorsResponse, or a Twirp::Error.
        sig { params(req: MonolithTwirp::Features::FeatureSync::V1::SynchronizeActorsRequest, env: T.untyped).returns(T.any(MonolithTwirp::Features::FeatureSync::V1::SynchronizeActorsResponse, Twirp::Error)) }
        def synchronize_actors(req, env)
          if req.added_actors.size > ACTOR_LIMIT
            return Twirp::Error.invalid_argument("too many actors", argument: "added_actors")
          end
          if req.deleted_actors.size > ACTOR_LIMIT
            return Twirp::Error.invalid_argument("too many actors", argument: "deleted_actors")
          end

          added_actors_req_ids = req.added_actors.map { |actor| actor.actorid }
          deleted_actors_req_ids = req.deleted_actors.map { |actor| actor.actorid }

          ActiveRecord::Base.connected_to(role: :writing) do
            GitHub.logger.info("synchronize_actors starting FlipperFeature.findby", "feature_flag.key" => req.name)
            feature = FlipperFeature.find_by(name: req.name)
            GitHub.logger.info("synchronize_actors finished FlipperFeature.findby", "feature_flag.key" => req.name)

            if feature.nil?
              return Twirp::Error.not_found("feature flag with name #{req.name} not found")
            end

            GitHub.logger.info("synchronize_actors starting mysql transaction", "feature_flag.key" => req.name)
            ::FlipperFeature.transaction do
              if !req.added_actors.empty?
                # SELECT `flipper_gates`.* FROM `flipper_gates` WHERE `flipper_gates`.`flipper_feature_id` = 13 AND `flipper_gates`.`name` = 'actors' AND `flipper_gates`.`value` IN (req.added_actors)
                existing_actor_gates = FlipperGate.where(flipper_feature_id: feature.id, name: "actors", value: req.added_actors.map { |actor| actor.actorid })
                actor_id_to_add = added_actors_req_ids - existing_actor_gates.map { |actor_gate| actor_gate.value }
                actor_id_to_add.each do |actor_id|
                  begin
                    # create makes a new record but does not bulk insert, it would have been better to use insert_all as it bulk inserts
                    # actors, but we'd need to retry inserting everything again after doing another read and repeat this in a loop a few times.
                    # There is also upsert_all but it does not have the ! variant and there are risks when duplicate key
                    # https://thehub.github.com/epd/engineering/products-and-services/dotcom/testing/linting/find-or-create/#upsert-risks
                    FlipperGate.create!({ flipper_feature_id: feature.id, name: "actors", value: actor_id })
                  rescue ActiveRecord::RecordNotUnique
                    log_fields = {
                      "gh.actor.id" => actor_id,
                      "feature_flag.key" => feature.name
                    }
                    GitHub.logger.info("duplicate entry creating actor for feature from feature sync api, ignoring because it does not need to error.", log_fields)
                  end
                end
              end
              if !req.deleted_actors.empty?
                FlipperGate.where(flipper_feature_id: feature.id, name: "actors", value: deleted_actors_req_ids).destroy_all
              end

              # mark the feature as updated
              feature.exclusion_rule = 1
              feature.rollout_updated_at = Time.at(Time.now.utc)
              feature.save!
            end
            GitHub.logger.info("synchronize_actors finished mysql transaction", "feature_flag.key" => req.name)
          end

          payload = {
            feature_name: req.name,
            operation: "synchronize_actors",
            added_actors: added_actors_req_ids.empty? ? [] : added_actors_req_ids,
            deleted_actors: deleted_actors_req_ids.empty? ? [] : deleted_actors_req_ids,
          }
          GitHub.instrument "feature.synchronize_actors", payload
          MonolithTwirp::Features::FeatureSync::V1::SynchronizeActorsResponse.new
        end

        def require_arguments(env, arguments)
          arguments.each do |argument|
            next if env[:input].public_send(argument).present?
            return Twirp::Error.invalid_argument("must be provided", argument: argument.to_s)
          end
          nil
        end

        # Now that we are rescuing on ActiveRecord::RecordNotUnique, the function now returns a different
        # value on success which is the return value from the last executed statement in each conditional block
        def apply_percentage(feature, gate_name, gate_defined, gate_value)
          existing = feature.flipper_gates.find_by(name: gate_name)
          if !existing.nil?
            if gate_defined
              existing.value = gate_value.round(2)
              existing.save!
            else
              existing.destroy
            end
          elsif gate_defined
            newgate = FlipperGate.create(flipper_feature_id: feature.id, name: gate_name, value: gate_value.round(2))
            newgate.save!
          end
        rescue ActiveRecord::RecordNotUnique => e
          Failbot.report!(e, gate_name: "#{gate_name}", gate_value: "#{gate_value}", feature_name: "#{feature.name}")
          GitHub.dogstats.increment("github.feature_flag_gate_record_not_unique.count", tags: ["gate_name:#{gate_name}"])
          nil
        end

        def sync_group_gates(feature, group_gate_defined, group_gate_values)
          existing_grp_gates = feature.flipper_gates.where(name: "groups")
          group_gates_to_add = T.let([], T::Array[String])
          group_gates_to_delete = T.let([], T::Array[String])

          if group_gate_defined
            existing_grp_gate_vals = existing_grp_gates.map { |group| group.value }
            group_gates_to_add = group_gate_values - existing_grp_gate_vals
            group_gates_to_delete = existing_grp_gate_vals - group_gate_values
          else
            group_gates_to_delete = existing_grp_gates.map { |group| group.value }
          end

          if group_gates_to_add.any? || group_gates_to_delete.any?
            ::FlipperGate.transaction do
              group_gates_to_add.each do |group|
                new_group_gate = FlipperGate.create(
                  flipper_feature_id: feature.id,
                  name: "groups",
                  value: group
                )
                new_group_gate.save!
              end

              existing_grp_gates.where(value: group_gates_to_delete).destroy_all if group_gates_to_delete.any?
            end
          end
        end
      end
    end
  end
end
