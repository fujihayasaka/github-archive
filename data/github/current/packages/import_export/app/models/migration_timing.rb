# typed: true
# frozen_string_literal: true

class MigrationTiming < ApplicationRecord::Domain::Migrations
  belongs_to :migration

  validates :migration, presence: true
  validates :action, presence: true
  validates :time_elapsed, presence: true

  ALLOWED_ACTIONS = {
    export:           0,
    prepare:          1,
    conflicts:        2,
    map_records:      3,
    unlock:           4,
    import:           5,
    download_archive: 6,
    upload_archive:   7,
    retry_import:     8,
  }.freeze

  enum :action, ALLOWED_ACTIONS

  class << self
    def record(migration, action, &block)
      result, duration = time(block)
      create(migration: migration, action: action, time_elapsed: duration)
      result
    end

    private

    def time(block)
      start_time = Time.now
      [block.call, (Time.now - start_time).round]
    end
  end
end
