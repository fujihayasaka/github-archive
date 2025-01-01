# frozen_string_literal: true

class TimelineComponent < ApplicationComponent
  attr_reader :subject

  def initialize(subject)
    @subject = subject
  end

  def render?
    items.any?
  end

  def items
    @items ||=
      versions.filter_map do |version|
        TimelineItemComponent.for_version(version, subject: subject)
      end
  end
end
