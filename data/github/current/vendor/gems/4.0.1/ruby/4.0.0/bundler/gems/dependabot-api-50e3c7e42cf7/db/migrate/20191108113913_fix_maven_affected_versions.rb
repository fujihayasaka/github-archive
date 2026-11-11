# frozen_string_literal: true

require "github/version_ranges"

class FixMavenAffectedVersions < ActiveRecord::Migration[6.0]
  def up
    SecurityAdvisory.where(package_manager: "maven").find_in_batches do |rows|
      rows.each do |advisory|
        advisory.affected_versions.map! do |version_range|
          convert_version(version_range)
        end
        advisory.save!
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Maven version backfill is not reversible"
  end

  private

  def convert_version(version_range)
    say "Converting #{version_range}..."

    ::GitHub::VersionRanges.convert_to_maven(version_range)
  rescue ::GitHub::VersionRanges::InvalidRangeError
    say "Failed to convert #{version_range}!", false

    version_range
  end
end
