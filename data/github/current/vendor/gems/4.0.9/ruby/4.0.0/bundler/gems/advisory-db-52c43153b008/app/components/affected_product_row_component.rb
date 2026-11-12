# frozen_string_literal: true

class AffectedProductRowComponent < ApplicationComponent
  attr_reader :vendor, :product, :versions, :index

  def initialize(vendor: nil, product: nil, versions: [], index: 0, disabled: false)
    @vendor = vendor
    @product = product
    @versions = normalize_versions(versions.presence || [])
    @index = index
    @disabled = disabled
  end

  def disabled?
    @disabled
  end

  # Extract just the version strings for display in the form
  def version_strings
    versions.map { |v| v.is_a?(Hash) ? v["version"] : v }
  end

  private

  # Normalize versions to always be an array of hashes with version and status
  def normalize_versions(vers)
    vers.map do |v|
      if v.is_a?(Hash)
        { "version" => v["version"], "status" => v["status"].presence || "affected" }
      else
        { "version" => v, "status" => "affected" }
      end
    end
  end
end
