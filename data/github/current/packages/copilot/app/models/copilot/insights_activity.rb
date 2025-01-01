# typed: strict
# frozen_string_literal: true

module Copilot
  class InsightsActivity < ApplicationRecord::Copilot
    # NOTE
    # Writes to this table take place in the github/copilot-usage-service repo.

    self.table_name = "copilot_insights_activities"

    extend T::Helpers
    include ::Instrumentation::Model
    include Copilot::Helpers

    DATA_COLUMNS = %i[
      engagement_events
      loc_suggested
      loc_accepted
      code_suggestion_events
      code_suggestion_events_accepted
      prs_merged
      pr_lead_time
      commit_count
    ]

    # one InsightsActivity can belong to many copilot entity memberships
    # because copilot usage for a user is tracked across all entities the user is part of
    # regardless of the entity that gives the user the copilot seat
    has_many :copilot_memberships,
      class_name: "Copilot::EntityMembership",
      foreign_key: :copilot_insights_activities_id,
      dependent: :destroy,
      inverse_of: :copilot_activity

    # one InsightsActivity only belongs to one platform entity membership because platform usage is tracked for the entity the user belongs to
    has_one :platform_membership,
      class_name: "Copilot::EntityMembership",
      foreign_key: :copilot_platform_activities_id,
      dependent: :destroy,
      inverse_of: :platform_activity

    before_save :update_timestamps, if: -> { :state_changed? }

    sig { params(organization: ::Organization).returns(ActiveRecord::Relation) }
    def self.for_organization(organization)
      joins(:copilot_memberships).where(copilot_memberships: { entity_id: organization.id })
    end

    DATA_COLUMNS.each do |attr|
      attribute attr, PackedIntegerArray.new

      define_method("#{attr}=") do |value|
        super(PackedIntegerArray::Array.from(value))
      end
    end

    sig { params(metric: Symbol).returns(T::Hash[Date, Integer]) }
    def activity_metric_by_day(metric:)
      return {} unless DATA_COLUMNS.include?(metric) && self[metric].present?

      # Reverse because the end of the array is the most recent date
      self[metric].reverse.each_with_index.each_with_object({}) do |(value, idx), hash|
        date = self["#{metric}_updated_at".to_sym].to_date - idx
        hash[date] = value
      end
    end

    private

    sig { void }
    def update_timestamps
      DATA_COLUMNS.each do |attr|
        next unless changed_attributes.include?(attr)
        updated_at_column = "#{attr}_updated_at".to_sym
        self[updated_at_column] = Time.now.utc
      end
    end
  end
end
