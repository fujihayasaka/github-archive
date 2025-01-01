# typed: true
# frozen_string_literal: true

class CollectionVideoFactory
  ALLOWED_HOSTS = [
    "www.youtube.com",
    "youtube.com",
    "www.youtu.be",
    "youtu.be",
  ].freeze

  def build_from_url(url)
    metadata = build_video_metadata(url)
    if !metadata[:title].blank?
      metadata[:title] = metadata[:title].truncate(40)
      collection_video = CollectionVideo.new(metadata)
    end
    collection_video
  end

  private def build_video_metadata(url)
    metadata = {}
    host = URI(url).host

    if !ALLOWED_HOSTS.include?(host)
      return metadata
    end

    case host
    when /\A(www\.)?(youtube\.com|youtu\.be)\z/
      if url.include?("embed")
        metadata[:url] = url
        id = url.split("/").last.split("?").first
        metadata[:thumbnail_url] = build_youtube_thumbnail_url(id)
        url_with_metadata = "https://www.youtube.com/watch?v=#{id}"
        metadata[:title], metadata[:description] = CollectionItemMetadata.build_from_url(url_with_metadata)
      else
        id = url.split("v=").last
        metadata[:url] = "https://www.youtube.com/embed/#{id}"
        metadata[:thumbnail_url] = build_youtube_thumbnail_url(id)
        metadata[:title], metadata[:description] = CollectionItemMetadata.build_from_url(url)
      end
    end
    metadata
  end

  private def build_youtube_thumbnail_url(id)
    "https://img.youtube.com/vi/#{id}/0.jpg"
  end
end
