# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class DirectAbilitiesOnSubjectForActor < Platform::Loader
        BATCH_SIZE = 1_000

        def self.load(actor_id:, actor_type:, subject_id:, subject_type:)
          self.for(actor_type, subject_type).load([actor_id, subject_id])
        end

        def initialize(actor_type, subject_type)
          @actor_type = actor_type
          @subject_type = subject_type
        end

        # entries is an Array of [actor_id, subject_ids] that we're trying to look up
        # actor_ids are all ids of type @actor_type
        # subject_ids are all ids of type @subject_type
        def fetch(entries)
          results = Hash.new { |h, k| h[k] = [] }
          entries.uniq.sort.each_slice(BATCH_SIZE).each do |batch|
            abilities = batch.map do |actor_id, subject_id|
              ::Ability.where(actor_id: actor_id, subject_id: subject_id)
            end.reduce(:or)

            abilities = abilities.where(
              actor_type: @actor_type,
              subject_type: @subject_type,
              priority: ::Ability.priorities[:direct])

            abilities.each do |ability|
              results[[ability.actor_id, ability.subject_id]] << ability
            end
          end
          results
        end
      end
    end
  end
end
