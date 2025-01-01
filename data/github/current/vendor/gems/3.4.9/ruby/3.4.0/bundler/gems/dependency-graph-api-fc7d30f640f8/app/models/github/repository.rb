module GitHub
  class Repository < ApplicationRecord
    establish_connection Rails.configuration.database_configuration.fetch("github").fetch(Rails.env)
    self.table_name = "repositories"
  end
end
