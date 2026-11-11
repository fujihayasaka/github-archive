# typed: true
# frozen_string_literal: true

# Used in GitHub::Tests::ClusterDependenciesTracker
#
# Parses the backtrace and extracts the following information:
#   - graceful degradation method: with_database_error_fallback, render_nothing_if_database_fails
#   - view_component, example: view: repository/_container_header.html.erb:51 - component: repositories/underline_nav_component.rb:31
#   - callback, example: after_commit
#   - filtered_backtrace: array of backtrace lines filtered by 'filter_by'
#   - frame: frame fetched by GitHub::FormattedStackLocation
class GitHub::BacktraceParser
  attr_reader :metadata, :filter_by

  def initialize(backtrace, filter_by: nil)
    @backtrace = backtrace
    @filter_by = filter_by
    @metadata = { filtered_backtrace: [] }
  end

  def parse
    @backtrace.each do |backtrace_location|
      frame = backtrace_location.to_s

      if metadata[:gd_method].nil?
        matches = frame.match(/(app\/helpers\/resilience_helper\.rb|lib\/github\/resilience_mixin\.rb).* `(?<method_name>.*)'/)
        metadata[:gd_method] = matches[:method_name] if matches
      end

      if metadata[:view].nil? && frame.include?("app/views/")
        matches = frame.match(/app\/views\/(?<view>.*):in/)
        metadata[:view] = matches[:view] if matches
      end

      if metadata[:component].nil? && frame.include?("app/components/")
        matches = frame.match(/app\/components\/(?<component>.*):in/)
        metadata[:component] = matches[:component] if matches
      end

      if metadata[:callback].nil? && frame.include?("lib/github/callback_instrumenter.rb")
        matches = frame.match(/lib\/github\/callback_instrumenter.*block in (?<callback>.*)'/)
        metadata[:callback] = matches[:callback] if matches
      end

      if metadata[:filtered_backtrace].length < 5 && !frame.include?("track")
        if filter_by.empty?
          metadata[:filtered_backtrace] << frame
        else
          metadata[:filtered_backtrace] << frame if frame.match?(Regexp.union(filter_by))
        end
      end
    end
  end

  def graceful_degradation_method
    metadata[:gd_method]
  end

  def view_component
    view_component = ""
    view_component += "view: #{metadata[:view]}" if metadata[:view]
    view_component += " - component: #{metadata[:component]}" if metadata[:component]
    view_component
  end

  def callback
    metadata[:callback]
  end

  def filtered_backtrace
    metadata[:filtered_backtrace]
  end

  def frame
    location = GitHub::FormattedStackLocation.from_location(@backtrace.shift) unless @backtrace.empty?
    location&.description
  end
end
