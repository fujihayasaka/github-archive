# typed: strict
# frozen_string_literal: true

# Internal: Basic timeline interface. Subclasses will just provide placeholder
# objects (`Timeline::Placeholder`) while this class takes care of the rest.
class Timeline::BaseTimeline
  extend T::Generic
  include GitHub::Memoizer

  abstract!

  # Public: Create timeline instance for the given subject and viewer
  #
  # subject        - Subject of the timeline, used in subclasses to
  #                  compile the list of placeholders
  # viewer         - User viewing the timeline of the given subject
  # filter_options - Hash of options passed to the timeline instance
  sig { params(subject: T.untyped, viewer: T.nilable(User), filter_options: T::Hash[Symbol, T.untyped]).void }
  def initialize(subject, viewer:, filter_options: {})
    @subject = subject
    @viewer = viewer
    @filter_options = filter_options
  end

  # Public: Provides promise resolving to all timeline items
  sig { returns(Promise[T::Array[T.untyped]]) }
  memoize def async_values
    async_filtered_placeholders.then do |placeholders|
      Promise.all(placeholders.map(&:async_value)).then do |values|
        values.compact
      end
    end
  end

  # Public: Provides promise resolving to all timeline item placeholders
  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  memoize def async_filtered_placeholders
    async_sorted_placeholders.then do |placeholders|
      since = filter_options[:since]
      next placeholders unless since

      placeholders.select do |placeholder|
        placeholder.filter_datetime > since
      end
    end
  end

  # Public: Provides promise resolving to the total count of timeline items
  sig { returns(Promise[Integer]) }
  memoize def async_total_count
    async_placeholders.then(&:size)
  end

  private

  sig { overridable.returns(T.untyped) }
  attr_reader :subject

  sig { returns(T.nilable(User)) }
  attr_reader :viewer

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :filter_options


  # Internal: Returns the placeholders sorted according to their sort key.
  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_sorted_placeholders
    async_placeholders.then do |placeholders|
      if subject.respond_to?(:async_base_repository)
        T.unsafe(subject).async_base_repository.then do |_base_repo|
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
  sig { abstract.returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_placeholders; end

  # Internal: Returns the `Platform::Object` classes of the requested `item_types`.
  sig { returns(T::Array[T.class_of(Platform::Objects::Base)]) }
  memoize def requested_item_types

    requested_item_types = filter_options[:item_types]
    requested_item_types ||= Platform::Unions::PullRequestTimelineItems.possible_types

    if filter_options[:exclude_item_types].present?
      excluded_names = Array(filter_options[:exclude_item_types])
      requested_item_types.reject! { |requested_item_type| excluded_names.include?(requested_item_type.graphql_name) }
    end
    requested_item_types
  end

  # Internal: Returns the type names of the requested `item_types`.
  sig { returns(T::Array[String]) }
  memoize def requested_item_type_names
    requested_item_types.map(&:graphql_name)
  end

  sig do
    type_parameters(:U)
      .params(blk: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  end
  def track_time(&blk)
    timer = Timer.start
    value = yield
    timer.stop

    GitHub.dogstats.distribution("timeline.dist.issue.sort", timer.elapsed_ms)
    value
  end
end
