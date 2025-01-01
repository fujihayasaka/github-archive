# typed: true
# frozen_string_literal: true

module TopicFeedHelper
  include ActionView::Helpers::TagHelper

  YOUTUBE_EMBED_SYNTAX = /\[\/\/youtube-embed-unfurl\/\/\]\:\s#\s\(.*\)/
  YOUTUBE_ID = /(?<=\]\:\s#\s\().*(?=\))/

  def topic_feed_flavored_markdown(description)
    return unless description.present?

    new_description = description.lines.map do |line|
      if line.starts_with?(YOUTUBE_EMBED_SYNTAX)
        convert_line_to_youtube_embed_code(line)
      else
        GitHub::Goomba::MarkdownPipeline.to_html(line)
      end
    end

    safe_join(new_description)
  end

  def convert_line_to_youtube_embed_code(line)
    youtube_id = line[YOUTUBE_ID]

    content_tag(
      :div,
      content_tag(
        :iframe,
        nil,
        src: "https://www.youtube.com/embed/#{youtube_id}?rel=0%26autoplay=0",
        frameborder: "0",
        title: "",
        allowfullscreen: true,
      ),
      class: "video-responsive",
    )
  end
end
