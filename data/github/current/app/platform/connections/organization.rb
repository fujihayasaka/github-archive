# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Organization < Connections::Base
      description "A list of organizations managed by an enterprise."

      total_count_field
    end
  end
end
