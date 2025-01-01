# typed: true
# frozen_string_literal: true

class Platform::Models::SingleSelectFieldOption

  delegate :name, :name_html, :color, :description, :description_html, :id, to: :option
  alias :option_id :id

  attr_accessor :platform_type_name

  delegate_missing_to :project_field

  sig { params(project_field: MemexProjectColumn, option: MemexProjectColumn::Settings::OptionEntry, v2: T::Boolean).void }
  def initialize(project_field, option, v2: true)
    @project_field = project_field
    @option = option
    @platform_type_name = v2 ? "ProjectV2SingleSelectFieldOption" : "ProjectNextSingleSelectFieldOption"
  end

  private

  attr_reader :option, :project_field
end
