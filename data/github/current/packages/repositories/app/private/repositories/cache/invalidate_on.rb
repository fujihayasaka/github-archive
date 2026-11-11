# typed: true
# frozen_string_literal: true

module Repositories
  module Cache
    class InvalidateOn < T::Enum
      enums do
        DiskUsage = new("disk_usage")
        Extract = new("extract")
        Fork = new("fork")
        Purge = new("purge")
        Push = new("push")
        Star = new("star")
        Updated = new("updated")
        Watch = new("watch")
      end
    end
  end
end
