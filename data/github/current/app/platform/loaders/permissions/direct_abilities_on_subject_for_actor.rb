# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class DirectAbilitiesOnSubjectForActor < Platform::Loader
        include Scientist

        BATCH_SIZE = 1_000

        def self.load(actor_id:, actor_type:, subject_id:, subject_type:)
          self.for(actor_type, subject_type).load([actor_id, subject_id])
        end

        def initialize(actor_type, subject_type)
          @actor_type = actor_type
          @subject_type = subject_type
        end

        # entries is an Array of [actor_id, subject_id] that we're trying to look up
        # actor_ids are all ids of type @actor_type
        # subject_ids are all ids of type @subject_type
        def fetch(entries)
          results = Hash.new { |h, k| h[k] = [] }
          entries.uniq.sort.each_slice(BATCH_SIZE).each do |batch|
            abilities = if ::FeatureFlag.vexi.enabled?(:optimized_direct_abilities_loader, default: false)
              abilities_for_batch(batch)
            else
              science "optimized_direct_abilities_loader" do |e|
                e.context(batch_size: batch.size)
                e.use { legacy_abilities_for_batch(batch) }
                e.try { abilities_for_batch(batch) }
                e.compare do |control, candidate|
                  GitHub.dogstats.increment("direct_abilities_on_subject_for_actor.batch_strategy", tags: ["strategy:#{batch_strategy(batch)}"])
                  control.sort_by(&:id) == candidate.sort_by(&:id)
                end
              end
            end

            abilities.each do |ability|
              results[[ability.actor_id, ability.subject_id]] << ability
            end
          end
          results
        end

        private

        def abilities_for_batch(batch)
          actor_ids = batch.map(&:first).uniq
          subject_ids = batch.map(&:last).uniq

          if actor_ids.size == 1 || subject_ids.size == 1
            # Common case: either single actor or single subject
            # (e.g. loading permissions for a user across multiple repos, or loading permissions for multiple users on a single repo)
            ::Ability.where(
              actor_id: actor_ids,
              subject_id: subject_ids,
              actor_type: @actor_type,
              subject_type: @subject_type,
              priority: ::Ability.priorities[:direct])
          else
            # Uncommon case: many actors, many subjects
            # (e.g. loading permissions for multiple users across multiple repos in a team)
            # Can't take full advantage of indexes
            legacy_abilities_for_batch(batch)
          end
        end

        def legacy_abilities_for_batch(batch)
          batch.map do |actor_id, subject_id|
            ::Ability.where(actor_id: actor_id, subject_id: subject_id)
          end.reduce(:or).where(
            actor_type: @actor_type,
            subject_type: @subject_type,
            priority: ::Ability.priorities[:direct]
          )
        end

        # For Scientist: determines the "strategy" of the batch for better analysis of results
        # No need to have this level of detail long-term, but it helps us confirm the optimized query is used
        def batch_strategy(batch)
          actor_ids = batch.map(&:first).uniq
          subject_ids = batch.map(&:last).uniq

          if subject_ids.size == 1 && actor_ids.size == 1
            :single_actor_and_subject
          elsif subject_ids.size == 1
            :single_subject
          elsif actor_ids.size == 1
            :single_actor
          else
            :mixed
          end
        end
      end
    end
  end
end
