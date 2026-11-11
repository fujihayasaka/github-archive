# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Payloads
    # Shared label serialization struct used by all dashboard surface payloads.
    # This is part of the shared dashboard surface infrastructure.
    class Label < T::Struct
      const :color, T.nilable(String)
      const :description, T.nilable(String)
      const :id, Integer
      const :name, String
      const :nameHtml, T.nilable(String)
    end
  end
end
