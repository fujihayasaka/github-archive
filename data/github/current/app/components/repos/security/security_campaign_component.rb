# typed: true
# frozen_string_literal: true

class Repos::Security::SecurityCampaignComponent < ApplicationComponent
  def initialize(campaign_with_counts:, campaign_path:, **system_arguments)
    @campaign_with_counts = campaign_with_counts
    @campaign_path = campaign_path
    @system_arguments = system_arguments
  end

  attr_reader :campaign_path

  def name
    @campaign_with_counts.name_for_display
  end

  def closed_count
    @campaign_with_counts.closed_count
  end

  def total_count
    @campaign_with_counts.total_count
  end

  def closed_percentage
    @campaign_with_counts.closed_percentage
  end

  def days_left_display
    "#{pluralize(@campaign_with_counts.days_left.abs, 'day')} #{@campaign_with_counts.days_left < 0 ? ' overdue' : 'left'}"
  end
end
