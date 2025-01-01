# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldIterationValue
  include GitHub::Relay::GlobalIdentification

  attr_reader :iteration_id, :title, :duration, :start_date, :title_html, :field_value
  attr_accessor :platform_type_name

  delegate_missing_to :@field_value

  def self.load_from_global_id(id)
    Platform::Loaders::ActiveRecord.load(::MemexProjectColumnValue, id.to_i, security_violation_behaviour: :nil).then do |field_value|
      next unless field_value

      field_value.async_memex_project_column.then do |field|
        new(field_value, field.settings_all_iteration(field_value.value))
      end
    end
  end

  def initialize(field_value, iteration)
    @field_value = field_value
    @iteration_id = iteration["id"]
    @title = iteration["title"]
    @duration = iteration["duration"]
    @start_date = iteration["start_date"]
    @title_html = iteration["title_html"]
    @platform_type_name = "ProjectV2ItemFieldIterationValue"
  end
end
