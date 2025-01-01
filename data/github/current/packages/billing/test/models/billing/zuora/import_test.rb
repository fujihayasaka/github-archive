# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::ImportTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  context ".find" do
    test "returns valid Import object" do
      completed_import_id = "2c92c0fa67881a1501678a73651d5fdd"
      with_live_zuora("zuora/import") do
        import = Billing::Zuora::Import.find(completed_import_id)
        assert_equal import.status, "Completed"
      end
    end
  end
end
