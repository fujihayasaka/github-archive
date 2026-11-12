# frozen_string_literal: true

module AdvisoryDB
  module GlobalVariables
    IN_SIMULATED_PUBLICATION_STRING = "IN_SIMULATED_PUBLICATION"
    IN_SIMULATED_PUBLICATION = false

    def self.assign_in_simulated_publication(value)
      value_before = const_get(IN_SIMULATED_PUBLICATION_STRING)
      const_set(IN_SIMULATED_PUBLICATION_STRING, value)
      yield
    ensure
      const_set(IN_SIMULATED_PUBLICATION_STRING, value_before)
    end

    def self.in_simulated_publication?
      const_get(IN_SIMULATED_PUBLICATION_STRING)
    end
  end
end
