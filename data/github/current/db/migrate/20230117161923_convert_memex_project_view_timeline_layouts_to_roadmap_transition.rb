# typed: true
# frozen_string_literal: true

require "github/transitions/20230117161923_convert_memex_project_view_timeline_layouts_to_roadmap"

class ConvertMemexProjectViewTimelineLayoutsToRoadmapTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::ConvertMemexProjectViewTimelineLayoutsToRoadmap.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
