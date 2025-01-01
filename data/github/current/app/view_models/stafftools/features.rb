# rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage
# typed: true
# frozen_string_literal: true

module Stafftools
  module Features
    include ActionView::Helpers::UrlHelper
    URL_HELPERS = UrlHelpers

    def feature_link(feature, show_percentage_of_time:)
      link = ActionController::Base.helpers.link_to(feature.name, URL_HELPERS.devtools_feature_flag_path(feature))

      if show_percentage_of_time && feature.percentage_of_time_value > 0
        ActionController::Base.helpers.safe_join([link, " @ #{feature.percentage_of_time_value}%"])
      else
        link
      end
    end

    def dev_portal_feature_link(feature, show_percentage_of_time:, show_custom_groups:)
      link = ActionController::Base.helpers.link_to(feature.name, "https://devportal.githubapp.com/feature-flags/#{feature.name}/overview")
      if show_percentage_of_time && feature.percentage_of_time > 0
        ActionController::Base.helpers.safe_join([link, " @ #{feature.percentage_of_time}%"])
      elsif show_custom_groups
        ActionController::Base.helpers.safe_join([link, " groups: #{feature.custom_groups}"])
      else
        link
      end
    end

    class FeatureGatesForUser
      attr_accessor :name, :in_actor_gate, :in_boolean_gate, :in_percentage_actor_gate, :in_percentage_time_gate, :in_custom_group, :percentage_of_actors, :percentage_of_time, :custom_groups

      def initialize(attributes = {})
        @name = attributes["name"]
        @in_actor_gate = attributes["InActorGate"]
        @in_boolean_gate = attributes["InBooleanGate"]
        @in_percentage_actor_gate = attributes["InPercentageActorGate"]
        @in_percentage_time_gate = attributes["InPercentageTimeGate"]
        @in_custom_group = attributes["InCustomGroupGate"]
        @percentage_of_actors = attributes["percentage_of_actors"].to_f rescue 0.0
        @percentage_of_time = attributes["percentage_of_time"].to_f rescue 0.0
        @custom_groups = attributes["custom_groups"]
      end
    end

    # Returns hash with features by gate type
    # Hash values are an Array of Arrays: [[FlipperFeature, Link]]
    def enabled_feature_flags_by_gate_type(actor, current_user)
      # check if enabled for current user
      if GitHub.flipper[:enabled_by_gate_type_refactor].enabled?(current_user)
        features = FlipperFeature.connection.select_all(Arel.sql(<<-SQL, actor_id: actor.flipper_id))
          SELECT
            flipper_features.name,
            CASE WHEN actor_gates.flipper_feature_id IS NOT NULL THEN 1 ELSE 0 END AS InActorGate,
            CASE WHEN boolean_gates.flipper_feature_id IS NOT NULL THEN 1 ELSE 0 END AS InBooleanGate,
            CASE WHEN percentage_of_actors.flipper_feature_id IS NOT NULL THEN 1 ELSE 0 END AS InPercentageActorGate,
            CASE WHEN percentage_of_time.flipper_feature_id IS NOT NULL THEN 1 ELSE 0 END AS InPercentageTimeGate,
            CASE WHEN custom_groups.flipper_feature_id IS NOT NULL THEN 1 ELSE 0 END AS InCustomGroupGate,
            percentage_of_actors.value AS percentage_of_actors,
            percentage_of_time.value AS percentage_of_time,
            custom_groups.group_names AS custom_groups
          FROM flipper_features
          LEFT JOIN flipper_gates AS actor_gates
            ON flipper_features.id = actor_gates.flipper_feature_id
            AND actor_gates.name = 'actors'
            AND actor_gates.value = :actor_id
          LEFT JOIN flipper_gates AS boolean_gates
            ON flipper_features.id = boolean_gates.flipper_feature_id
            AND boolean_gates.name = 'boolean'
            AND (boolean_gates.value = 'true' OR boolean_gates.value = '1')
          LEFT JOIN flipper_gates AS percentage_of_actors
            ON flipper_features.id = percentage_of_actors.flipper_feature_id
            AND percentage_of_actors.name = 'percentage_of_actors'
            AND percentage_of_actors.value > 0
          LEFT JOIN flipper_gates AS percentage_of_time
            ON flipper_features.id = percentage_of_time.flipper_feature_id
            AND percentage_of_time.name = 'percentage_of_time'
            AND percentage_of_time.value > 0
          LEFT JOIN (
            SELECT flipper_feature_id, GROUP_CONCAT(value, ', ') AS group_names
            FROM flipper_gates
            WHERE name = 'groups'
            GROUP BY flipper_feature_id
          ) AS custom_groups
             ON flipper_features.id = custom_groups.flipper_feature_id
          WHERE actor_gates.flipper_feature_id IS NOT NULL
            OR boolean_gates.flipper_feature_id IS NOT NULL
            OR percentage_of_actors.flipper_feature_id IS NOT NULL
            OR percentage_of_time.flipper_feature_id IS NOT NULL
            OR custom_groups.flipper_feature_id IS NOT NULL
        SQL

        percentage_actors_gate = Flipper::Gates::PercentageOfActors.new
        return features.each_with_object({ actor_gates: [], possibly_gates: [], inherited_gates: [] }) do |item, result|
          feature = FeatureGatesForUser.new(item)
          if feature.in_actor_gate == 1
            result[:actor_gates] << [feature, dev_portal_feature_link(feature, show_percentage_of_time: false, show_custom_groups: false)]
          end
          if feature.in_boolean_gate == 1 || feature.percentage_of_time == 100
            result[:inherited_gates] << [feature, dev_portal_feature_link(feature, show_percentage_of_time: false, show_custom_groups: false)]
          end
          if feature.in_percentage_actor_gate == 1
            ctx = Flipper::FeatureCheckContext.new(
              feature_name: feature.name,
              values: Flipper::GateValues.new(percentage_of_actors: feature.percentage_of_actors),
              thing: actor
            )
            if percentage_actors_gate.open?(ctx)
              result[:inherited_gates] << [feature, dev_portal_feature_link(feature, show_percentage_of_time: false, show_custom_groups: false)]
            end
          end
          if feature.in_percentage_time_gate == 1 && feature.percentage_of_time < 100 && feature.percentage_of_time > 0
            result[:possibly_gates] << [feature, dev_portal_feature_link(feature, show_percentage_of_time: true, show_custom_groups: false)]
          end
          if feature.in_custom_group == 1
            result[:possibly_gates] << [feature, dev_portal_feature_link(feature, show_percentage_of_time: false, show_custom_groups: true)]
          end
        end
      end

      FlipperFeature.all.each_with_object({ actor_gates: [], possibly_gates: [], inherited_gates: [] }) do |feature, features|
        gates = feature.open_gates(actor)
        next unless gates.any?
        if gates.all? { |f| f.key == :actors } # these gates can be removed with effect.
          features[:actor_gates] << [feature, feature_link(feature, show_percentage_of_time: false)]
        elsif gates.any? { |f| f.key == :percentage_of_time && feature.percentage_of_time_value > 0 }
          features[:possibly_gates] << [feature, feature_link(feature, show_percentage_of_time: true)]
        else
          features[:inherited_gates] << [feature, feature_link(feature, show_percentage_of_time: false)]
        end
      end
    end

  end
end

# rubocop:enable GitHub/FeatureManagement/NoFlipperFeatureUsage
