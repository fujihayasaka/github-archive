# frozen_string_literal: true

require "test_helper"
require "advisory_db/global_variables"

module AdvisoryDB
  class GlobalVariablesTest < ActiveSupport::TestCase
    test "global variable behavior works as expected" do
      AdvisoryDB::GlobalVariables.assign_in_simulated_publication(true) do
        assert AdvisoryDB::GlobalVariables.in_simulated_publication?

        AdvisoryDB::GlobalVariables.assign_in_simulated_publication(false) do
          refute AdvisoryDB::GlobalVariables.in_simulated_publication?
        end

        assert AdvisoryDB::GlobalVariables.in_simulated_publication?
      end

      refute AdvisoryDB::GlobalVariables.in_simulated_publication?
    end
  end
end
