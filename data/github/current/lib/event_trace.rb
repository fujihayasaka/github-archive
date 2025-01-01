# typed: true
# frozen_string_literal: true

class EventTrace
  attr_reader :command, :duration, :arguments, :tags, :locations

  class BacktraceDepth
    # https://github.com/ruby/ruby/pull/13080 changes the backtrace for initialize calls,
    # removing Class#new for Ruby 3.5 previews
    # NEW_CLASS_DEPTH will be 0 for these versions, and we have to return the full
    # backtrace from caller_locations.
    # For Ruby 3.4, we remove the first line through caller_locations because the second
    # line is what we're interested in.
    #
    # Calculating this variable uses the same method as the Ruby PR above
    # https://github.com/ruby/ruby/pull/13080/files#diff-7624f95f521b3333de8c687d70c2574aa31616cebf9504d8bcf673865fbf6ecdR475-R486
    NEW_CLASS_DEPTH = Class.new do
      attr_reader :c
      def initialize(from)
        @c = caller.length - from.length
      end
    end.new(caller(0)).c
  end

  ROOT_SLASH = "#{Rails.root}/"
  APP_SLASH = "#{Rails.root}/app/"

  def initialize(command, duration, arguments, tags: [])
    @command = command
    @duration = duration
    @arguments = arguments
    @locations = caller_locations(BacktraceDepth::NEW_CLASS_DEPTH + 1)
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
