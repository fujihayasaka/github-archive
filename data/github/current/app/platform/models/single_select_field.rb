# typed: true
# frozen_string_literal: true

class Platform::Models::SingleSelectField
  include GitHub::Relay::GlobalIdentification

  attr_reader :project_field
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

  sig { params(project_field: MemexProjectColumn).void }
  def initialize(project_field)
    @project_field = project_field
    @options = project_field.settings_options_objects_all.map do |option|
      Platform::Models::SingleSelectFieldOption.new(project_field, option)
    end
    @platform_type_name = "ProjectV2SingleSelectField"
  end

  sig { params(names: T.nilable(T::Array[String])).returns(T::Array[Platform::Models::SingleSelectFieldOption]) }
  def options(names: nil)
    if names.nil?
      @options
    else
      normalized_names = names.compact.map(&:downcase).to_set
      @options.select { |option| normalized_names.include?(option.name.downcase) }
    end
  end
end
