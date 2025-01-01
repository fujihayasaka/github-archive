# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class DeleteNoisySponsorsPatreonActivities < Base
      START_TIME = "2023-12-05 10:06:19" # merge time for https://github.com/github/github/pull/301689
      END_TIME = "2023-12-05 14:38:49"   # merge time for https://github.com/github/github/pull/303122
      iterate_over :database_table, params: {
        model_class: SponsorsActivity,
        conditions: "timestamp BETWEEN '#{START_TIME}' AND '#{END_TIME}' AND payment_source = 1 " \
          "AND action IN (0, 1, 2)", # new_sponsorship, cancelled_sponsorship, tier_change
        columns: %i[id action sponsorable_id sponsor_id sponsors_tier_id old_sponsors_tier_id],
      }
      DELETE_BATCH_SIZE = 100

      sig { returns T.nilable(Integer) }
      attr_reader :total_activities_deleted

      sig { returns T.nilable(T::Set[Integer]) }
      attr_reader :sponsor_ids

      sig { returns T.nilable(T::Set[Integer]) }
      attr_reader :sponsorable_ids

      sig { returns T.nilable(T::Set[Integer]) }
      attr_reader :processed_activity_ids

      sig { override.void }
      def after_initialize
        @total_activities_deleted = T.let(0, T.nilable(Integer))
        @sponsor_ids = T.let(Set.new, T.nilable(T::Set[Integer]))
        @sponsorable_ids = T.let(Set.new, T.nilable(T::Set[Integer]))
        @processed_activity_ids = T.let(Set.new, T.nilable(T::Set[Integer]))
        @activity_ids_to_delete_in_batch = T.let([], T.nilable(T::Array[Integer]))
      end

      sig { override.void }
      def perform
        super

        if @total_activities_deleted
          verb = dry_run? ? "Would have deleted" : "Deleted"
          log("#{verb} #{@total_activities_deleted} Patreon activities")
        end
        log("#{@sponsor_ids.size} sponsors affected") if @sponsor_ids
        log("#{@sponsorable_ids.size} maintainers affected") if @sponsorable_ids
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        @activity_ids_to_delete_in_batch = []
        user_ids = items.values.flat_map { |activity| [activity[:sponsor_id], activity[:sponsorable_id]] }.uniq
        user_logins_by_id = T.let(User.where(id: user_ids).pluck(:id, :login).to_h, T::Hash[Integer, String])

        items.each do |id, activity_data|
          next if @processed_activity_ids&.include?(id.to_i) # already processed this activity in a previous batch

          # Load all the duplicates for this activity, even if those duplicates are not in this batch:
          activity_and_duplicates = duplicate_activities_from(activity_data)

          calculate_activity_ids_to_delete(activity_data, user_logins_by_id, activity_and_duplicates)
        end

        delete_duplicate_activities_in_batch
      end

      private

      sig { void }
      def delete_duplicate_activities_in_batch
        return if @activity_ids_to_delete_in_batch.blank?

        verb = dry_run? ? "Would delete" : "Deleting"
        total_to_delete = @activity_ids_to_delete_in_batch.size
        units = total_to_delete == 1 ? "activity" : "activities"
        log("#{verb} #{total_to_delete} #{units}")

        if dry_run?
          if @total_activities_deleted
            @total_activities_deleted += total_to_delete
          end
          return
        end

        @activity_ids_to_delete_in_batch.each_slice(DELETE_BATCH_SIZE) do |activity_ids_to_delete|
          log("Deleting batch of activity IDs: #{activity_ids_to_delete.sort}")
          write_to(model_class: SponsorsActivity) do
            total_deleted = SponsorsActivity.where(id: activity_ids_to_delete).delete_all
            units = total_deleted == 1 ? "activity" : "activities"
            log("Deleted #{total_deleted} #{units}")
            if @total_activities_deleted
              @total_activities_deleted += total_deleted
            end
          end
        end
      end

      sig do
        params(
          activity: T::Hash[Symbol, T.untyped],
          user_logins_by_id: T::Hash[Integer, String],
          activities_and_duplicates: T::Array[SponsorsActivity]
        ).void
      end
      def calculate_activity_ids_to_delete(activity, user_logins_by_id, activities_and_duplicates)
        activity_ids_including_duplicates = unprocessed_duplicate_activity_ids_from(activities_and_duplicates)
        return if activity_ids_including_duplicates.empty?

        @processed_activity_ids += activity_ids_including_duplicates if @processed_activity_ids
        original_activity_id = activity_ids_including_duplicates.first
        activity_ids_to_delete = activity_ids_including_duplicates.drop(1) # keep the oldest activity
        return if activity_ids_to_delete.empty? # nothing to do

        action = activity[:action]
        sponsor_id = activity[:sponsor_id]
        sponsorable_id = activity[:sponsorable_id]
        @sponsor_ids << sponsor_id if @sponsor_ids
        @sponsorable_ids << sponsorable_id if @sponsorable_ids

        verb = dry_run? ? "would delete" : "deleting"
        tier_summary = if action == "tier_change"
          " (tier ##{activity[:old_sponsors_tier_id]} => ##{activity[:sponsors_tier_id]})"
        end
        ids_summary = activity_ids_to_delete.map(&:to_s).join(", ")
        sponsor_login = user_logins_by_id[sponsor_id]
        sponsor_summary = if sponsor_login.present?
          "@#{sponsor_login} (##{sponsor_id})"
        else
          "##{sponsor_id}"
        end
        sponsorable_login = user_logins_by_id[sponsorable_id]
        sponsorable_summary = if sponsorable_login.present?
          "@#{sponsorable_login} (##{sponsorable_id})"
        else
          "##{sponsorable_id}"
        end
        log("Preserving activity ##{original_activity_id}, #{verb} #{activity_ids_to_delete.size} #{action} " \
          "Patreon activities for sponsor #{sponsor_summary} to maintainer #{sponsorable_summary}#{tier_summary}: " \
          "#{ids_summary}")

        if @activity_ids_to_delete_in_batch
          @activity_ids_to_delete_in_batch += activity_ids_to_delete
        end
      end

      sig { params(activities_and_duplicates: T::Array[SponsorsActivity]).returns(T::Set[Integer]) }
      def unprocessed_duplicate_activity_ids_from(activities_and_duplicates)
        activity_ids = activities_and_duplicates.map(&:id).compact.to_set
        activity_ids -= @processed_activity_ids if @processed_activity_ids
        activity_ids
      end

      sig { params(activity_data: T::Hash[Symbol, T.untyped]).returns(T::Array[SponsorsActivity]) }
      def duplicate_activities_from(activity_data)
        SponsorsActivity.order(:timestamp)
          .select(:id, :action, :sponsorable_id, :sponsor_id, :sponsors_tier_id, :old_sponsors_tier_id)
          .where(where_conditions_for(activity_data))
          .to_a
      end

      sig { params(activity: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def where_conditions_for(activity)
        action = activity[:action]

        conditions = {
          action: action,
          sponsor_id: activity[:sponsor_id],
          sponsorable_id: activity[:sponsorable_id],
          payment_source: :patreon,
          timestamp: START_TIME..END_TIME,
        }

        if action == "tier_change"
          conditions[:old_sponsors_tier_id] = activity[:old_sponsors_tier_id]
          conditions[:sponsors_tier_id] = activity[:sponsors_tier_id]
        end

        conditions
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::DeleteNoisySponsorsPatreonActivities.new(args).run
end
