# typed: true
# frozen_string_literal: true

# Used when rendering a partial for live updates: much of our
# live updates happen via a call to #show_partial in a controller
# that requests a partial specified in the template.
module ShowPartial
  extend T::Helpers
  requires_ancestor { ActionController::Base }

  ConditionalAccessExempt = %w[
    tree/recently_touched_branches_list
  ]

  # Maps partial names to dom ids.
  #
  # The key MUST be symbols matching the partial name like
  # "pull_requests/form_actions".
  #
  # The value SHOULD be an ID selector for the element on the page.
  PartialMapping = {
    sidebar: "#partial-discussion-sidebar",
    timeline: "#partial-timeline",
    timeline_marker: "#partial-timeline-marker",
    visible_comments_header: "#partial-visible-comments-header",
    merging: "#partial-pull-merging",
    form_actions: "#partial-new-comment-form-actions",
    new_message: "#partial-new-discussion-message",
    title: "#partial-discussion-header",
    state_button_wrapper: "#issue-state-button-wrapper",
    pull_request_tab_count: "#pull-requests-repo-tab-count",
    issue_tab_count: "#issues-repo-tab-count",
  }

  private

  def conditional_access_exempt_partial?(partial)
    return false unless partial
    ConditionalAccessExempt.include?(partial)
  end

  # Public: Render a set of partials back to the browser for immediate
  # updating. You'll want to do this on actions when you don't want the
  # user to wait for a live update to come through to get the content
  # update.
  #
  # partials- Hash where keys are Symbols from PartialMapping.keys and
  #           values are rendered templates in string form.
  # status - Optional status value to render, default :ok.
  #
  # Returns nothing.
  def render_update_content_json(partials, status: :ok)
    partial_content = partials.map do |partial, rendered_string|
      [page_selector_for_partial_name(partial), rendered_string]
    end.to_h

    render json: { "updateContent" => partial_content }, status: status
  end

  # Internal: Get document selector for partial name.
  #
  # Also see TimelineMarkerHelper in helpers/timeline_marker_helper.rb.
  #
  # sym - Symbol partial name in PartialMapping allowlist.
  #
  # Returns a String DOM selector.
  def page_selector_for_partial_name(sym)
    # Special case timeline marker to include the timestamp of
    # X-Timeline-Last-Modified header. Ensures we only try replace the
    # originally requested range of comments.
    if sym == :timeline_marker && (last_modified = helpers.discussion_last_modified_at)
      "#partial-timeline-marker[data-last-modified='#{last_modified.httpdate}']"
    elsif sym == :timeline && (last_modified = helpers.discussion_last_modified_at)
      "#partial-timeline[data-last-modified='#{last_modified.iso8601(9)}']"
    else
      PartialMapping[sym]
    end
  end
end
