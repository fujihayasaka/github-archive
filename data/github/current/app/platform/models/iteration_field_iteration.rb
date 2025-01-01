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
    @title_html = config["title_html"]
    @id = config["id"]

    @platform_type_name = "ProjectV2IterationFieldIteration"
  end
end
