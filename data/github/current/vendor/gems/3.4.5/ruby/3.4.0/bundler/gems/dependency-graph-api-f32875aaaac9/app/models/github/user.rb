module GitHub
  class User < ApplicationRecord
    # Highly specialized model used to grab corresponding user object data from dotcom.
    # Currently not in use because of inability to test database initialization between dotcom and dependency graph.
    # If needed in future, remember to resolve database initialization issues between the two services.
    establish_connection Rails.configuration.database_configuration.fetch("github").fetch(Rails.env)
    self.table_name = "users"
    self.inheritance_column = "nil"
  end
end
