# typed: strict
# frozen_string_literal: true

module ApplicationController::RequestTimingDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  sig { params(base: T.class_of(ApplicationController)).void }
  def self.included(base)
    base.class_eval do
      before_action :start_request_timing
      after_action :finish_request_timing
    end
  end

  private

  sig { void }
  def start_request_timing
    request_timing.start_controller_action
  rescue # rubocop:disable Lint/GenericRescue
    # It's not worth crashing the request if we can't start the request timings
  end

  # Stop timing the request and publish request breakdown timings
  # for the controller action.
  #
  # It is a no-op if the request is not successful or if no
  # operations were tracked by RequestTiming#track.
  sig { void }
  def finish_request_timing
    return unless response.successful?
    request_timing.finish_controller_action
  rescue # rubocop:disable Lint/GenericRescue
    # It's not worth crashing the request if we can't publish the request timings
  end

  # Get the RequestTiming instance to track the time spent in a given
  # operation, aggregated through the lifetime of the request.
  #
  # Example:
  #   # In controller action, use the track method:
  #   def index
  #     # ...
  #     request_timing.track(:load_discussion_comments) do
  #       load_discussion_comments
  #     end
  #   end
  sig { returns(GitHub::RequestTiming) }
  memoize def request_timing
    common_tags = {
      controller: controller_name_with_namespace,
      action: action_name,
      logged_in: logged_in?,
      deployed_to: GitHub.deployed_to,
      category: request_category
    }

    GitHub::RequestTiming.new(common_tags: common_tags)
  end

  # Returns the controller name with the name space separated by an underscore.
  #
  # Example:
  #   A controller named "Foo::Bar::BazController" returns "foo_bar_baz"
  sig { returns String }
  memoize def controller_name_with_namespace
    controller_path.gsub("/", "_")
  end
end
