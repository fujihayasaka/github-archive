# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class UserContentEdit < Connections::Base
      description "A list of edits to content."

      total_count_field
    end
  end
end
