# typed: true
# frozen_string_literal: true

class Site::Readme::Topics::HeroComponent < ApplicationComponent
  include SvgHelper

  def initialize(topic:)
    @topic = topic
  end
end
