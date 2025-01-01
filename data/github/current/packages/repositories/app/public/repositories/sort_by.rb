# typed: strict
# frozen_string_literal: true

module Repositories
  class SortBy < T::Enum
    enums do
      # rubocop:disable Style/WordArray
      CreatedAtThenId = new(["created_at", "id"])
      UpdatedAtThenId = new(["updated_at", "id"])
      PushedAtThenId = new(["pushed_at", "id"])
      NameThenId = new(["name", "id"])
      FullNameThenId = new(["owner_login", "name", "id"])
      WatcherCountThenId = new(["watcher_count", "id"])
      CreatedAt = new(["created_at"])
      UpdatedAt = new(["updated_at"])
      PushedAt = new(["pushed_at"])
      Name = new(["name"])
      FullName = new(["owner_login", "name"])
      WatcherCount = new(["watcher_count"])
      Id = new(["id"])
      # rubocop:enable Style/WordArray
    end

    sig { params(direction: GH::Pagination::Sort::Direction).returns(T::Array[GH::Pagination::Sort]) }
    def to_gh_sort(direction:)
      self.serialize.map { |sort| GH::Pagination::Sort.new(field: "repositories.#{sort}", direction: direction) }
    end
  end
end
