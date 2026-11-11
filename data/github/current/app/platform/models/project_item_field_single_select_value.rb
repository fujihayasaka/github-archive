# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldSingleSelectValue
  include GitHub::Relay::GlobalIdentification

  delegate :name, :name_html, :color, :description, :description_html, to: :option

  # option_id
  delegate :id, to: :option, prefix: :option

  attr_accessor :platform_type_name

  delegate_missing_to :field_value

  def self.load_from_global_id(id)
    Platform::Loaders::ActiveRecord.load(::MemexProjectColumnValue, id.to_i, security_violation_behaviour: :nil).then do |field_value|
      next unless field_value

      field_value.async_memex_project_column.then do |field|
        new(field_value, T.unsafe(T.must(field).single_select_option_object(field_value.value)))
      end
    end
  end

  sig { params(field_value: MemexProjectColumnValue, selected_option: MemexProjectColumn::Settings::OptionEntry).void }
  def initialize(field_value, selected_option)
    @field_value = field_value
    @option = selected_option
    @platform_type_name = "ProjectV2ItemFieldSingleSelectValue"
  end

  private

  attr_reader :option, :field_value
end
