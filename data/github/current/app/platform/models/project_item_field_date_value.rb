# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldDateValue
  include GitHub::Relay::GlobalIdentification

  attr_reader :date, :field_value
  attr_accessor :platform_type_name

  delegate_missing_to :@field_value

  def self.load_from_global_id(id)
    Platform::Loaders::ActiveRecord.load(::MemexProjectColumnValue, id.to_i, security_violation_behaviour: :nil).then do |field_value|
      new(field_value) if field_value
    end
  end

  def initialize(field_value)
    @field_value = field_value
    @value = field_value.value
    @platform_type_name = "ProjectV2ItemFieldDateValue"
  end
end
