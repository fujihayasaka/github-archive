# typed: true
# frozen_string_literal: true

# Internal: Basic timeline interface. Subclasses will just provide placeholder
# objects (`Timeline::Placeholder`) while this class takes care of the rest.
class Timeline::BaseTimeline
  # Public: Create timeline instance for the given subject and viewer
  #
  # subject        - Subject of the timeline, used in subclasses to
  #                  compile the list of placeholders
  # viewer         - User viewing the timeline of the given subject
  # filter_options - Hash of options passed to the timeline instance
  def initialize(subject, viewer:, filter_options: {})
    @subject = subject
    @viewer = viewer
    @filter_options = filter_options
  end

  # Public: Provides promise resolving to all timeline items
  #
  # Returns Promise resolving to an Array of timeline items
  def async_values
    return @async_values if defined?(@async_values)

    @async_values = async_filtered_placeholders.then do |placeholders|
      Promise.all(placeholders.map(&:async_value))
    end
  end

  # Public: Provides promise resolving to all timeline item placeholders
  #
  # Returns Promise resolving to an Array of placeholders
  def async_filtered_placeholders
    return @async_filtered_placeholders if defined?(@async_filtered_placeholders)

    @async_filtered_placeholders = async_sorted_placeholders.then do |placeholders|
      since = filter_options[:since]
      next placeholders unless since

      placeholders.select do |placeholder|
        placeholder.filter_datetime > since
      end
    end
  end

  # Public: Provides promise resolving to the total count of timeline items
  #
  # Returns Promise resolving to an Integer
  def async_total_count
    return @async_total_count if defined?(@async_total_count)

    @async_total_count = async_placeholders.then(&:size)
  end

  private

  attr_reader :subject, :viewer, :filter_options

  # Internal: Returns the placeholders sorted according to their sort key.
  #
  # Returns Promise resolving to an Array of Timeline::Placeholders
  def async_sorted_placeholders
    async_placeholders.then do |placeholders|
      if subject.respond_to?(:async_base_repository)
        subject.async_base_repository.then do |_base_repo|
          StableSorter.new(placeholders).sort_by(&:sort_key)
        end
      else
        track_time do
          placeholders.sort_by(&:sort_key)
        end
      end
    end
  end

  # Internal: Subclasses implement this method and return placeholder objects
  # (subclasses of `Timeline::Placeholder::Base`).
  #
  # Returns Promise resolving to an Array of Timeline::Placeholders
  def async_placeholders
    raise Platform::Errors::Internal, "Not implemented"
  end

  # Internal: Returns the `Platform::Object` classes of the requested `item_types`.
  #
  # Returns Array of Classes
  def requested_item_types
    return @requested_item_types if defined?(@requested_item_types)

    @requested_item_types = filter_options[:item_types]
    @requested_item_types ||= Platform::Unions::PullRequestTimelineItems.possible_types

    if filter_options[:exclude_item_types].present?
      excluded_names = Array(filter_options[:exclude_item_types])
      @requested_item_types.reject! { |requested_item_type| excluded_names.include?(requested_item_type.graphql_name) }
    end
    @requested_item_types
  end

  # Internal: Returns the type names of the requested `item_types`.
  #
  # Returns Array of Strings
  def requested_item_type_names
    return @requested_item_type_names if defined?(@requested_item_type_names)
    @requested_item_type_names = requested_item_types.map(&:graphql_name)
  end

  def track_time
    timer = Timer.start
    value = yield
    timer.stop

    GitHub.dogstats.distribution("timeline.dist.issue.sort", timer.elapsed_ms)
    value
  end
end
