# typed: strict
# frozen_string_literal: true

module Notifications
  module SortOrder
    DEFAULT = T.let("desc", String)
    OPTIONS = T.let({
      "desc" => "Newest to oldest",
      "asc" => "Oldest to newest",
    }.freeze, T::Hash[String, String])
  end
end
