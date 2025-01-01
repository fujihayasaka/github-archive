# typed: strict
# frozen_string_literal: true

#
#   `id` int(11) NOT NULL AUTO_INCREMENT,
#   `title` varbinary(200) NOT NULL,
#   `external_post_id` int(11) NOT NULL,
#   `url` varchar(175) NOT NULL,
#   `description` varbinary(700) DEFAULT NULL,
#   `author` varchar(75) NOT NULL,
#   `featured` tinyint(1) NOT NULL DEFAULT '0',
#   `published_at` datetime NOT NULL,
#   `created_at` datetime NOT NULL,
#   `updated_at` datetime NOT NULL,

class Marketplace::Story < ApplicationRecord::Collab
  self.table_name = "marketplace_blog_posts"

  include GitHub::Relay::GlobalIdentification

  extend GitHub::Encoding
  force_utf8_encoding :title, :description

  validates :title, presence: true
  validates :external_post_id, presence: true
  validates :url, presence: true
  validates :author, presence: true
  validates :published_at, presence: true

  sig { params(rss_item: T.untyped).void }
  def self.update_or_create_from_rss_feed(rss_item)
    external_id = rss_item.children.find { |child| child.name == "post-id" }.text

    post = find_by(external_post_id: external_id) || new(external_post_id: external_id)

    author = rss_item.children.find { |child| child.name == "creator" }.text

    html_description = rss_item.at("description").text
    description = Nokogiri::HTML.fragment(html_description).first_element_child.text

    post.update(title: rss_item.at("title").text,
                url: rss_item.at("link").text,
                author: author,
                description: description,
                published_at: rss_item.at("pubDate").text)
  end
end
