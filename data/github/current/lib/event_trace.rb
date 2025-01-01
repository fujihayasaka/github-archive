# typed: true
# frozen_string_literal: true

class EventTrace
  attr_reader :command, :duration, :arguments, :tags, :locations

  ROOT_SLASH = "#{Rails.root}/"
  APP_SLASH = "#{Rails.root}/app/"

  def initialize(command, duration, arguments, tags: [])
    @command = command
    @duration = duration
    @arguments = arguments
    @locations = caller_locations(2)
    @tags = tags
  end

  def milliseconds
    duration.to_i
  end

  def pretty_printed_arguments
    "#{arguments.inspect}\n"
  end

  def formatted_backtrace
    backtrace.join("\n")
  end

  def backtrace
    @backtrace ||= @locations.map { |line| line.to_s.sub ROOT_SLASH, "" }
  end

  def formatted_stack_locations
    @locations.map do |location|
      GitHub::FormattedStackLocation.from_location(location)
    end
  end

  # First stack frame in the app directory
  def first_app_location
    @first_app_location ||= @locations.find do |frame|
      frame.absolute_path&.start_with?(APP_SLASH)
    end
  end
end
