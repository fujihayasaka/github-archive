# typed: true
# frozen_string_literal: true

# Live update or comment requests set a X-Timeline-Last-Modified header on the
# XHR request to inform the server which discussion comments and events are
# already on the page. That way the backend only has to render new timeline
# events since a certain date. See Issue#timeline_for(user, since:).
#
# See app/assets/modules/github/legacy/behaviors/timeline_marker.js for the
# client side half that sets the header.
module TimelineMarkerHelper
  extend T::Helpers
  requires_ancestor { ActionView::Base }

  # Any controller using ShowPartial needs this. Used by
  # render_update_content_json in ShowPartial and _timeline_marker.html
  def discussion_last_modified_at
    if str = request.headers["X-Timeline-Last-Modified"]
      Time.parse(str)
    elsif secs = params[:since]
      Time.at(secs.to_i)
    else
      nil
    end
  end
end
