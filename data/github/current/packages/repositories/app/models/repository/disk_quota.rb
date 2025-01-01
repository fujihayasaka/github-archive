# typed: true
# frozen_string_literal: true

module Repository::DiskQuota
  extend T::Helpers

  requires_ancestor { Repository }

  # Public: is the repository nearing too much disk space?
  def above_warn_quota?
    quota = disk_quota(kind: :warn) * 1.gigabytes / 1.kilobytes
    quota == 0 ? false : disk_usage > quota
  end

  # Public: is the repository using too much disk space?
  def above_lock_quota?
    quota = disk_quota(kind: :lock) * 1.gigabytes / 1.kilobytes
    quota == 0 ? false : disk_usage > quota
  end
end
