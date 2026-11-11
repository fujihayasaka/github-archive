# typed: false
# frozen_string_literal: true

module Gist::Quota
  WARN_QUOTA = 50.megabytes / 1.kilobyte
  LOCK_QUOTA = 100.megabytes / 1.kilobyte

  # Public: is the gist nearing too much disk space?
  def above_warn_quota?
    disk_usage > WARN_QUOTA
  end

  # Public: is the gist using too much disk space?
  def above_lock_quota?
    disk_usage > LOCK_QUOTA
  end
end
