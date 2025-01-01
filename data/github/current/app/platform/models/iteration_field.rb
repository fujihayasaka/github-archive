# typed: true
# frozen_string_literal: true

class Platform::Models::IterationField
  include GitHub::Relay::GlobalIdentification

  attr_reader :configuration, :project_field
  attr_accessor :platform_type_name

  delegate_missing_to :@project_field

  # Set the base class of this platform model equal to the backing MemexProjectColumn.
  # This is required for prefilling associations.
  def self.base_class
    MemexProjectColumn.base_class
  end

  def self.load_from_global_id(id)
    Platform::Loaders::ActiveRecord.load(::MemexProjectColumn, id.to_i, security_violation_behaviour: :nil).then do |project_field|
      new(project_field) if project_field
    end
  end

  def initialize(project_field)
    @project_field = project_field
    @configuration = Platform::Models::IterationFieldConfiguration.new(project_field)
    @platform_type_name = "ProjectV2IterationField"
  end
end
