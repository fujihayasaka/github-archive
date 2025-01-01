# typed: strict
# frozen_string_literal: true

module Copilot
  class EntityMembership < ApplicationRecord::Copilot
    # NOTE
    # Writes to this table take place in the github/copilot-usage-service repo.

    self.table_name = "copilot_entity_memberships"

    extend T::Helpers
    include ::Instrumentation::Model
    include Copilot::Helpers

    belongs_to :user, class_name: "::User"
    belongs_to :entity, polymorphic: true, required: true, validate: true

    validates :entity_id, presence: true
    validates :entity_type, presence: true, inclusion: { in: %w(User EnterpriseTeam Business) }

    belongs_to :copilot_activity,
      class_name: "Copilot::InsightsActivity",
      foreign_key: :copilot_insights_activities_id,
      inverse_of: :copilot_memberships # many-to-one

    belongs_to :platform_activity,
      class_name: "Copilot::InsightsActivity",
      foreign_key: :platform_insights_activities_id,
      inverse_of: :platform_membership # one-to-one

    # member_on? returns whether or not 'user' was a member of 'entity'
    # on the provided day, using the contents of 'membership_history'
    sig { params(day: Date).returns(T::Boolean) }
    def member_on?(day)
      # calculate the number of days between the last membership_history update and the requested day, i.e.
      # the offset of the desired day into the 'membership_history' bit mask. For example,
      # if
      # - membership_history = 0b1101 which was last updated at yesterday
      # - day = 3d ago
      # then offset = 2, and the 2nd bit (0-indexed) represents encodes the membership history for that day.
      offset = (updated_at.to_date - day).to_i
      return false if offset < 0 # insufficient history or invalid date

      # this AND will be >0 if and only if the bit in the offset position of 'membership_history' is set
      mask = membership_history_mask
      return false unless mask
      mask & (1 << offset) > 0
    end

    # translate the 8-bit, big endian encoding stored in `membership_history` into a normal integer
    # - decode bytes into binary string with least significant bit on the right
    # - translate binary string to integer
    sig { returns(T.nilable(Integer)) }
    def membership_history_mask
      return unless membership_history

      decoded = membership_history.unpack1("B*")

      decoded.to_i(2)
    end

    sig do
      params(start_date: Date, end_date: Date).returns({
        engagement_events: Integer,
        code_suggestion_events: Integer,
        code_suggestion_events_accepted: Integer,
        loc_suggested: Integer,
        loc_accepted: Integer,
      })
    end
    def copilot_activity_for_period(start_date:, end_date:)
      result = {
        engagement_events: 0,
        code_suggestion_events: 0,
        code_suggestion_events_accepted: 0,
        loc_suggested: 0,
        loc_accepted: 0,
      }
      activity = copilot_activity
      return result if activity.nil?

      engagement_events_by_day = activity.activity_metric_by_day(metric: :engagement_events)
      code_suggestion_events_by_day = activity.activity_metric_by_day(metric: :code_suggestion_events)
      code_suggestion_events_accepted_by_day = activity.activity_metric_by_day(metric: :code_suggestion_events_accepted)
      loc_suggested_by_day = activity.activity_metric_by_day(metric: :loc_suggested)
      loc_accepted_by_day = activity.activity_metric_by_day(metric: :loc_accepted)

      ((start_date - Copilot::Metrics::Aggregators::Base::LOOKBACK_DAYS)..end_date).map do |date|
        if member_on?(date)
          result[:engagement_events] += engagement_events_by_day[date].to_i
        end
      end

      (start_date..end_date).map do |date|
        if member_on?(date)
          result[:code_suggestion_events] += code_suggestion_events_by_day[date].to_i
          result[:code_suggestion_events_accepted] += code_suggestion_events_accepted_by_day[date].to_i
          result[:loc_suggested] += loc_suggested_by_day[date].to_i
          result[:loc_accepted] += loc_accepted_by_day[date].to_i
        end
      end

      result
    end

    sig { params(organization: ::Organization).returns(ActiveRecord::Relation) }
    def self.for_organization(organization)
      where(entity: organization)
    end

    sig do
      params(start_date: Date, end_date: Date).returns({
        prs_merged: Integer,
        pr_lead_time: Integer,
        commit_count: Integer,
        engagement_events: Integer,
      })
    end
    def velocity_activity_for_period(start_date:, end_date:)
      result = {
        prs_merged: 0,
        pr_lead_time: 0,
        commit_count: 0,
        engagement_events: 0,
      }
      activity = platform_activity
      return result if activity.nil? || copilot_activity.nil?

      engagement_events_by_day = T.must(copilot_activity).activity_metric_by_day(metric: :engagement_events)
      prs_merged_by_day = activity.activity_metric_by_day(metric: :prs_merged)
      pr_lead_time_by_day = activity.activity_metric_by_day(metric: :pr_lead_time)
      commit_count_by_day = activity.activity_metric_by_day(metric: :commit_count)

      ((start_date - Copilot::Metrics::Aggregators::Base::LOOKBACK_DAYS)..end_date).map do |date|
        if member_on?(date)
          result[:engagement_events] += engagement_events_by_day[date].to_i
        end
      end

      (start_date..end_date).map do |date|
        # sum activity regardless of membership history since presence of activity implies membership in an entity
        result[:prs_merged] += prs_merged_by_day[date].to_i
        result[:pr_lead_time] += pr_lead_time_by_day[date].to_i
        result[:commit_count] += commit_count_by_day[date].to_i
      end

      result
    end
  end
end
