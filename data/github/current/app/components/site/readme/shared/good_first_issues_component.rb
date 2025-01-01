# typed: true
# frozen_string_literal: true

class Site::Readme::Shared::GoodFirstIssuesComponent < ApplicationComponent
  def initialize(story:, contributing:)
    @story = story
    @contributing = contributing
  end

  def render?
    @contributing.present?
  end
end
