# typed: true
# frozen_string_literal: true

module GitHubModels
  class Kv
    class DataStore < ApplicationRecord::Domain::GitHubModels
      self.table_name = "models_key_values"
    end
  end
end
