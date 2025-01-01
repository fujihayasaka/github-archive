# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  class Commits < Base
    self.abstract_class = true

    connects_to database: { writing: :commits_primary, reading: :commits_readonly }
  end
end
