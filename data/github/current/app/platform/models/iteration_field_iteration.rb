# typed: true
# frozen_string_literal: true

class Platform::Models::IterationFieldIteration
  attr_reader :duration, :start_date, :id, :title, :title_html
  attr_accessor :platform_type_name

  delegate_missing_to :@project_field

  def initialize(project_field, config)
    @project_field = project_field
    @duration = config["duration"].to_i
    @start_date = config["start_date"]
    @title = config["title"]
    @title_html = sanitized_title_html(config)
    @id = config["id"]

    @platform_type_name = "ProjectV2IterationFieldIteration"
  end

  private

  def sanitized_title_html(config)
    if FeatureFlag.vexi.enabled?(:memex_iteration_xss_fix, default: true)
      title = @title || config["title_html"] || ""
      GitHub::Goomba::MemexTextColumnPipeline.to_html(title)
    else
      config["title_html"]
    end
  end
end
