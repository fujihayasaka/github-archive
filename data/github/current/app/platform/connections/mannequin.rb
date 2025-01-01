# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Mannequin < Connections::Base
      description "A list of mannequins."

      total_count_field
    end
  end
end
