# typed: false
#frozen_string_literal: true

module Platform
  module Loaders
    class AbilityMembershipCheck < Platform::Loader
      include Scientist

      MAX_VALUES_GROUP_SIZE = 20

      SELECTED_ATTRIBUTES = [:subject_type, :subject_id, :actor_type, :actor_id]

      SUBJECT_CONDITION = "subject_type = ? AND subject_id = ?"
      SUBJECT_CONDITION_IN = "subject_type = ? AND subject_id IN (?)"
      ACTOR_CONDITION = "actor_type = ? AND actor_id = ?"
      ACTOR_CONDITION_IN = "actor_type = ? AND actor_id IN (?)"

      def self.load(subject_type, subject_id, actor_type, actor_id)
        self.for.load([subject_type, subject_id, actor_type, actor_id])
      end

      def fetch(subjects_and_actors)
        results = []

        if subjects_and_actors.count > 1
          by_subject = subjects_and_actors.group_by { |q| [q[0], q[1]] }
          by_actor = subjects_and_actors.group_by { |q| [q[2], q[3]]  }

          # Running separate queries for each subject or actor since the loader
          # was timing out for a large number of subjects or actors.  Specifically
          # there were ~2000 different actors and ~400 different subjects.  It generated a big
          # query, with OR conditions and it was timing out on the database.
          if by_subject.count <= by_actor.count
            by_subject.each do |(subject_type, subject_id), actors|
              results += fetch_group_by(SUBJECT_CONDITION, ACTOR_CONDITION_IN,
                subject_type, subject_id, actors.group_by { |q| q[2] }, 3)
            end
          else
            by_actor.each do |(actor_type, actor_id), subjects|
              results += fetch_group_by(ACTOR_CONDITION, SUBJECT_CONDITION_IN,
                actor_type, actor_id, subjects.group_by { |q| q[0] }, 1)
            end
          end
        else
          values = subjects_and_actors.first
          results += ::Ability.direct.where("#{SUBJECT_CONDITION} AND #{ACTOR_CONDITION}", *values)
            .pluck(*SELECTED_ATTRIBUTES)
        end

        results.each_with_object(Hash.new { false }) do |(subject_type, subject_id, actor_type, actor_id), hash|
          hash[[subject_type, subject_id, actor_type, actor_id]] = true
        end
      end

      def fetch_group_by(condition1, condition2, type, id, by_values, id_position)
        results = []

        # only run the group by query when it exceeds the max size or has a single value type
        if by_values.count > 1 && by_values.count <= MAX_VALUES_GROUP_SIZE
          conditions = []
          condition_values = [type, id]

          by_values.each do |value_type, value_ids|
            conditions << condition2
            condition_values << value_type << value_ids.map { |q| q[id_position] }
          end

          results += ::Ability.direct.where("#{condition1} AND (#{conditions.join(" OR ")})", *condition_values)
            .pluck(*SELECTED_ATTRIBUTES)
        else
          by_values.each do |value_type, value_ids|
            condition_values = [type, id, value_type, value_ids.map { |q| q[id_position] }]
            results += ::Ability.direct.where("#{condition1} AND #{condition2}", *condition_values)
              .pluck(*SELECTED_ATTRIBUTES)
          end
        end

        results
      end
    end
  end
end
