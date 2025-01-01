# typed: true
# frozen_string_literal: true

class Teams::LargeTeamConfirmationDialogComponent < ApplicationComponent
  # Needed for avatar_class_names
  include AvatarHelper

  attr_reader :teams, :type, :threshold, :entity_name

  def initialize(teams:, type:, threshold:)
    @teams = teams
    @type = type
    @threshold = threshold

    @entity_name = @type.to_s.humanize.downcase
  end

  def render?
    teams.any?
  end

  def container_name
    entity_name
  end

  def confirm_text
    "Request Review"
  end

  def cancel_text
    "Don't request these teams"
  end
end
