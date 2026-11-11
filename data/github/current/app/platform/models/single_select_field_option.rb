# typed: true
# frozen_string_literal: true

class Platform::Models::SingleSelectFieldOption

  delegate :name, :color, :description, :id, to: :option
  alias :option_id :id

  attr_accessor :platform_type_name

  delegate_missing_to :project_field

  sig { params(project_field: MemexProjectColumn, option: MemexProjectColumn::Settings::OptionEntry).void }
  def initialize(project_field, option)
    @project_field = project_field
    @option = option
    @platform_type_name = "ProjectV2SingleSelectFieldOption"
  end

  def name_html
    if FeatureFlag.vexi.enabled?(:memex_iteration_xss_fix, default: true)
      GitHub::Goomba::MemexTextColumnPipeline.to_html(name || "")
    else
      option.name_html
    end
  end

  def description_html
    if FeatureFlag.vexi.enabled?(:memex_iteration_xss_fix, default: true)
      GitHub::Goomba::MemexTextColumnPipeline.to_html(description || "")
    else
      option.description_html
    end
  end

  private

  attr_reader :option, :project_field
end
