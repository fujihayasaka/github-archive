# typed: strict
# frozen_string_literal: true

module Spark
  class RuntimeAppOwner < ApplicationRecord::Copilot
    self.table_name = "runtime_app_owners"

    validates :permanent_name, presence: true, uniqueness: true, length: { maximum: 20 }
  end
end
