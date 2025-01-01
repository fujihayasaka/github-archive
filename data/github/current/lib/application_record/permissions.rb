# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class Permissions < Base
    include GitHub::MaxExecutionTime

    self.abstract_class = true

    connects_to database: { writing: :permissions_primary, reading: :permissions_readonly }
  end
end
