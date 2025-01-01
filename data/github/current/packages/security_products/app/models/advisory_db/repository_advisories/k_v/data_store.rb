# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  module RepositoryAdvisories
    class KV
      class DataStore < ApplicationRecord::Domain::RepositoriesCollab
        self.table_name = "repository_advisories_key_values"
      end
    end
  end
end
