# typed: true
# frozen_string_literal: true

class Platform::Models::IterationFieldConfiguration
  attr_reader :duration, :start_day, :iterations, :completed_iterations
  attr_accessor :platform_type_name

  delegate_missing_to :@project_field

  def initialize(project_field)
    @project_field = project_field
    @duration = 0
    @start_day = 0
    @iterations = []
    @completed_iterations = []
    @platform_type_name = "ProjectV2IterationFieldConfiguration"

    # override initial values is a settings configuration exists
    config = project_field.settings&.dig("configuration")
    if config
      @duration = config["duration"].to_i
      @start_day = config["start_day"].to_i
      @iterations = config["iterations"].map { |iteration| Platform::Models::IterationFieldIteration.new(project_field, iteration) }
      @completed_iterations = config["completed_iterations"].map { |iteration| Platform::Models::IterationFieldIteration.new(project_field, iteration) }
    end
  end
end
