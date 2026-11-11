# typed: strict
# frozen_string_literal: true

module DashboardSurface
  # Shared pagination struct used by all dashboard surface controllers.
  # Each surface constructs this from search results and passes it to
  # payload serializers.
  #
  # This is part of the shared dashboard surface infrastructure.
  class Pagination < T::Struct
    const :current_page, Integer
    const :total_pages, Integer
    const :total_count, Integer
  end
end
