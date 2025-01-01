# typed: false
# frozen_string_literal: true

class CollectionItemFactory
  def initialize
    @video_factory = CollectionVideoFactory.new
  end

  def build_from_slug(url)
    case url
    when /youtube\.com|youtu\.be/
      content = @video_factory.build_from_url(url)
      if content
        collection_item = CollectionItem.new(slug: url, content: content)
      end
    when /\A(www\.)?github\.com\z/
      content = find_content_by_url(url)
      collection_item = CollectionItem.new(slug: url, content: content)
    else
      content = find_content_by_url(url)
      unless content
        title, description = CollectionItemMetadata.build_from_url(url)
        if title && !title.empty?
          content = CollectionUrl.new(url: url, title: title.truncate(40), description: description)
        end
      end
      collection_item = CollectionItem.new(slug: url, content: content) if content
    end
    collection_item
  end

  private

  def extract_url_path(url)
    uri = URI.parse(url)
    uri.path.sub(%r{\A/}, "")
  end

  def find_content_by_url(url)
    url = extract_url_path(url)
    if url.include?("/")
      content = Repository.public_scope.with_name_with_owner(url)
    else
      content = User.find_by_login(url)
    end
    content
  end
end
