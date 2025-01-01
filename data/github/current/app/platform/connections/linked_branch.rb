# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class LinkedBranch < Connections::Base
      description "A list of branches linked to an issue."

      total_count_field
    end
  end
end
