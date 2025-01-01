# typed: true
# frozen_string_literal: true

require "github/goomba/video_tag_filter"

#
# Looks for links to videos and removes them if found. This is used by the CopilotSummaryInputPipeline to remove links to
# videos from summaries before sending them to the Copilot API (CAPI). Copilot cannot read the videos so removing the
# links to them is necessary so the links are not referenced.
#
# Because there are multiple ways to embed videos in a GitHub comment, this filter extends the regular VideoTagFilter
# and uses its regular logic to determine if we think a video was found. If we fall into one of those cases we
# return false to remove the node. Otherwise we forward along its return value.
#
module GitHub::Goomba
  class StripVideoLinkFilter < VideoTagFilter
    def call(node)
      res = super

      # node gets modified in place by VideoTagFilter so we need to check the original instance
      if node && node["gh:video-upload"]
        false
      else
        res
      end
    end
  end
end
