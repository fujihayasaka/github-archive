# typed: true
# frozen_string_literal: true

class IpAllowlistChecks::ResultsComponent < ApplicationComponent
  attr_reader :ip, :owner, :permitting_entries

  def initialize(ip:, owner:, permitting_entries:)
    @ip = ip
    @owner = owner
    @permitting_entries = permitting_entries
  end

  private

  def renderable_entries
    permitting_entries.map do |entry|
      if !owner.is_a?(Integration) && entry.owner_type == "Integration"
        "#{entry.allow_list_value} (#{entry.owner_name_and_type} requests only)"
      else
        entry.allow_list_value
      end
    end
  end
end
