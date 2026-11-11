# typed: true
# frozen_string_literal: true

class PullRequest::Loader::PullRequestTimeline < Issue::Loader::Timeline
  include TimelineHelper

  def initialize(context, pagination_params)
    @pull_request = context.pull_request
    super(context, pagination_params)
  end

  sig { returns(PullRequests::Timeline::PullRequestTimeline) }
  def timeline_model
    return @timeline_model if defined?(@timeline_model)

    filter_options = {
      visible_events_only: true,
      filter_closed_if_preceded_by_merged: @pull_request.merged?,
      cap_filter: @context.cap_filter,
      since: pagination_params[:timeline_since],
      exclude_item_types: pagination_params[:exclude_item_types],
    }

    # Limit the number of issue events loaded from the database
    # to the page size instead of loading ALL events. This is to help prevent timeouts
    # on PRs with very large numbers of timeline events (e.g. 10k+).
    filter_options[:first] = @page_size * 2
    filter_options[:total_count_optimization] = true

    @timeline_model = PullRequests::Timeline::PullRequestTimeline.for(@pull_request, @viewer, filter_options)
  end
end
