# typed: true
# frozen_string_literal: true

class Site::Readme::Shared::LinkImgComponent < ApplicationComponent
  def initialize(story:, dimensions:, image: "thumbnail", lazyload: false, topic_tag: true, build_in_margin: nil, build_in: false, shape: nil, rotate: false, photo: true, sizes: nil, podcast_badge: true)
    @story = story
    @dimensions = dimensions
    @image = image
    @lazyload = lazyload
    @topic_tag = topic_tag
    @build_in_margin = build_in_margin
    @build_in = build_in
    @shape = shape
    @rotate = rotate
    @photo = photo
    @sizes = sizes
    @podcast_badge = podcast_badge
  end

  def image_url
    return @story[:hero_image][:url] if @image == "hero"

    @story[:thumbnail][:url]
  end

  def build_in?
    @build_in
  end

  def set_build_in_margin?
    self.build_in? && @build_in_margin.present?
  end

  def circled?
    @shape == "circle"
  end

  def squared?
    @shape == "square"
  end

  def rotate?
    @rotate
  end

  def shaped?
    self.circled? || self.squared?
  end

  def img_classes
    "d-block width-full readme-link__img height-auto #{self.shaped? ? "position-absolute" : "position-relative"}"
  end

  def lazyload?
    @lazyload
  end

  def is_photo?
    @photo
  end

  def sizes
    @sizes.present? ? @sizes : "(max-width: 755px) 90vw, 45vw"
  end

  def topic
    @story[:topics]&.first
  end

  def topic?
    self.topic.present?
  end

  def show_topic_tag?
    @topic_tag && self.topic?
  end

  def show_podcast_badge?
    @podcast_badge && @story[:podcast?]
  end
end
