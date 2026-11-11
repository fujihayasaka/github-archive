# typed: true
# frozen_string_literal: true

# Tracks our progress scanning asset usage logs. See SyncAssetUsageSchedulerJob.
class Asset::SyncStatus < ApplicationRecord::Domain::Assets
  self.table_name = :asset_sync_statuses


  # Different markers can be tracked with a different name.
  VALID_NAMES = Set.new([
    "all", # github-cloud bucket on legacy s3 account
    "registry", # registry package files on new s3 account
  ])

  def self.set(name, marker)
    name_s = name.to_s
    if !VALID_NAMES.include?(name_s)
      raise ArgumentError, "Expected #{name.inspect} to be one of #{VALID_NAMES.to_a.inspect}"
    end

    bindings = { name: name_s, marker: marker.to_s }
    q = <<-SQL
      INSERT INTO asset_sync_statuses (
        name, marker, created_at, updated_at
      ) VALUES (
        :name, :marker, NOW(), NOW()
      ) ON DUPLICATE KEY UPDATE
        marker = VALUES(marker),
        updated_at = NOW()
    SQL

    ActiveRecord::Base.connected_to(role: :writing) { self.connection.insert(Arel.sql(q, **bindings)) }
  end

  def self.get(name)
    if st = where(name: name).first
      st.marker
    end
  end
end
