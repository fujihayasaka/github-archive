# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Milestone < Connections::Base
      description "The connection type for Milestone."

      total_count_field
    end
  end
end
