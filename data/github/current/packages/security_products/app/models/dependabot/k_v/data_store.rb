# typed: strict
# frozen_string_literal: true

module Dependabot
  class KV
    class DataStore < ApplicationRecord::Domain::RepositoriesNotify
      self.table_name = "dependabot_key_values"
    end
  end
end
