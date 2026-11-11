# typed: true
# frozen_string_literal: true

require "scientist"

module Platform
  module Loaders
    class Permission < Platform::Loader
      def self.load(actor, subject)
        actor = actor.ability_delegate
        subject = subject.ability_delegate

        return ::Promise.resolve(nil) unless actor && subject
        return ::Promise.resolve(nil) unless actor.ability_id && subject.ability_id

        # A simpler `actor == subject` triggers `method_missing` when using `CollectionProxy` instances as actors or subjects,
        # causing the entire association to be queried and loaded
        if actor.ability_type == subject.ability_type && actor.ability_id == subject.ability_id
          # everyone has autonomy over themselves
          return ::Promise.resolve(::Ability.actions[:admin])
        end

        self.for(actor.ability_type, subject.ability_type).load([actor.ability_id, subject.ability_id])
      end

      def initialize(actor_type, subject_type)
        @actor_type = actor_type
        @subject_type = subject_type
      end

      # Returns a hash of the form:
      # { [actor_id, subject_id] => action }
      # where action is the highest action the actor can perform on the subject
      def fetch(actor_and_subject_ids)
        # Let's track the number of actor_and_subject_ids we're fetching permissions for.
        # The underlying SQL query could be expensive when this number is high.
        # REF: https://github.com/github/fanout/issues/608#issuecomment-2018726571
        GitHub.dogstats.distribution("platform.loaders.permission.fetch.actor_and_subject_ids", actor_and_subject_ids.count)

        fetch_results_for(actor_and_subject_ids).each_with_object({}) do |(actor_id, subject_id, action), result|
          key = [actor_id, subject_id]
          current_action = result[key]

          if current_action.nil? || current_action < action
            result[key] = action
          end
        end
      end

      private

      # Returns all permissions for a given actor_type and subject_ids.
      #
      # The result is an array of arrays of the form:
      # [[actor_id, subject_id, action], [actor_id, subject_id, action], ...]
      def fetch_results_for(actor_and_subject_ids)
        GitHub.dogstats.distribution_time("platform.loaders.permission.fetch_results_for") do
          results = []
          # Group subjects by actor_id and fetch permissions for each actor individually.
          #
          # A hash of the form { actor_id => [subject_id, subject_id, ...] }
          grouped_by_actor_id = actor_and_subject_ids.each_with_object({}) do |(actor_id, subject_id), h|
            (h[actor_id] ||= []) << subject_id
          end

          # Let's track the number of actor_id groupings we're fetching permissions for.
          GitHub.dogstats.distribution("platform.loaders.permission.actor_id_groupings", grouped_by_actor_id.count)
          grouped_by_actor_id.each do |actor_id, subject_ids|
            partial_result = fetch_results_for_single_actor(actor_id, subject_ids)
            results.concat(partial_result)
          end

          results
        end
      end

      def fetch_results_for_single_actor(actor_id, subject_ids)
        case @actor_type
        when "GlobalIntegrationInstallation",
             "ScopedIntegrationInstallation",
             "SiteScopedIntegrationInstallation"
          ScopedInstallations::AuthorizationDetails::Loaders::Permission.load(
            @actor_type, actor_id, @subject_type, subject_ids
          )
        else
          if ::FeatureFlag.vexi.enabled_or_raise?(:permissions_loader_tracing) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            fetch_results_for_single_actor_via_permissions_with_tracing(actor_id, subject_ids)
          else
            fetch_results_for_single_actor_via_permissions(actor_id, subject_ids)
          end
        end
      end

      def fetch_results_for_single_actor_via_permissions_with_tracing(actor_id, subject_ids)
        trace_info = {
          "gh.actor_type" => @actor_type,
          "gh.subject_type" => @subject_type,
          "gh.actor_id" => actor_id,
          "gh.subject_ids_count" => subject_ids&.count,
        }

        GitHub.tracer.in_span("Platform::Loaders::Permission#fetch_results_for_single_actor_via_permissions", attributes: trace_info, kind: :internal) do |_span|
          fetch_results_for_single_actor_via_permissions(actor_id, subject_ids)
        end
      end

      def fetch_results_for_single_actor_via_permissions(actor_id, subject_ids)
        ::Permission.where(
          actor_type: @actor_type,
          subject_type: @subject_type,
          actor_id: actor_id,
          subject_id: subject_ids,
        ).pluck(
          :actor_id, :subject_id, :action,
        ).map do |actor_id, subject_id, action|
          # Because consumers of this method expect the action value to be an integer,
          # we need to explicitly convert it here.
          [actor_id, subject_id, ::Permission.actions[action]]
        end
      end
    end
  end
end
