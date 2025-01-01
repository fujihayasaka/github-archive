# typed: true
# frozen_string_literal: true

class GitHub::SQLCheckers::StacktraceParser
  FRAME_FORMAT = /
    \A
      \s*
      ([^:]+ | <.*>):         # abs_path
      (\d+)                   # line_number
      (?: :in \s ['`]([^']+)')?  # method
    \z
  /x

  FILES_TO_IGNORE = %w(experiment_cache)
  METHODS_TO_IGNORE = %w(with_user_timezone)

  def self.first_relevant_frame_info(backtrace)
    return unless backtrace.is_a?(Array)

    first_frame_regex = compose_first_frame_regex
    first_relevant_frame = backtrace.reverse.find { |f| f.to_s =~ first_frame_regex }
    return unless first_relevant_frame

    parsed_frame = GitHub::FailbotBacktrace::RailsRootPrefixProcessor.call(first_relevant_frame)
    match = parsed_frame.match(FRAME_FORMAT)

    path, line_number, method = match.captures

    # filter out any numbers from path and method to ensure no cache keys are included which would be too high
    # cardinality for a dd tag
    method.gsub!(/\d+/, "")
    path.gsub!(/\d+/, "")

    {
      path: path,
      line_number: line_number,
      method: method
    }
  end

  def self.compose_first_frame_regex
    ignore_files_regex = FILES_TO_IGNORE.map { |method| "(?!.*#{method})" }.join("")
    ignore_methods_regex = METHODS_TO_IGNORE.map { |file| "(?!.*#{file})" }.join("")

    Regexp.new("#{ignore_files_regex}#{ignore_methods_regex}app\/(controllers|models|components|views)\/")
  end
end
