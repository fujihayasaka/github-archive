# typed: true
# frozen_string_literal: true

class FlipperGate < ApplicationRecord::Domain::Features
  include GitHub::Validations
  include GitHub::BatchedScope

  DETERMINISTIC_TYPES = %w[actors boolean groups]
  PERCENTAGE_TYPES = %W[percentage_of_actors percentage_of_time]
  TYPES = DETERMINISTIC_TYPES + PERCENTAGE_TYPES
  FLIPPER_ID_SEPARATOR = ":".freeze

  STATE_MATRIX = {
    fully_enabled: "shipped",
    staff_shipped: "staff-shipped",
    actor_or_percentage: "testing",
    fully_disabled: "disabled",
  }.freeze

  validates :name, presence: true, inclusion: TYPES, unicode3: true
  validates :value, presence: true, unicode3: true
  belongs_to :flipper_feature

  scope :actor_gates, ->(actor_type: nil) {
    actor_type_param = actor_type.blank? ? "%" : "#{actor_type}:%"
    where("name = 'actors' AND value LIKE ?", actor_type_param)
  }

  scope :actor_gates_by_feature_id_and_filter_by, ->(flipper_feature_id, actor_type) {
    actor_type_param = actor_type.blank? ? "%" : "#{ActiveRecord::Base.sanitize_sql_like(actor_type)}#{FLIPPER_ID_SEPARATOR}%"
    where("name = 'actors' AND value LIKE ? AND flipper_feature_id = ?", actor_type_param, flipper_feature_id)
  }

  def actor_gate?
    name == "actors"
  end

  def self.non_actor_gates(flipper_feature_id)
    union_sql = [
      FlipperGate.where(flipper_feature_id: flipper_feature_id, name: Flipper::Gates::Boolean.new.key).to_sql, # rubocop:disable GitHub/FeatureManagement/NoFlipperGateUsage
      FlipperGate.where(flipper_feature_id: flipper_feature_id, name: Flipper::Gates::PercentageOfActors.new.key).to_sql, # rubocop:disable GitHub/FeatureManagement/NoFlipperGateUsage
      FlipperGate.where(flipper_feature_id: flipper_feature_id, name: Flipper::Gates::PercentageOfTime.new.key).to_sql, # rubocop:disable GitHub/FeatureManagement/NoFlipperGateUsage
      FlipperGate.where(flipper_feature_id: flipper_feature_id, name: Flipper::Gates::Group.new.key).to_sql, # rubocop:disable GitHub/FeatureManagement/NoFlipperGateUsage
    ].join(" UNION All ")
    FlipperGate.find_by_sql(union_sql) # rubocop:disable GitHub/FeatureManagement/NoFlipperGateUsage
  end

  # Internal: load the associated actor for this gate
  def actor
    GitHub::FlipperActor.from_flipper_id(value)
  end

  def actor_type
    GitHub::FlipperActor.class_name_from_flipper_id(value)
  end
end
