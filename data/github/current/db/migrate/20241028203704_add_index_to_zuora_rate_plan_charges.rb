# typed: true
# frozen_string_literal: true

class AddIndexToZuoraRatePlanCharges < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    change_table :zuora_rate_plan_charges, bulk: true do |t|
      t.virtual :billing_period, type: :string, limit: 32, as: "(`payload`->>'$.billingPeriod')"

      # We need to explicitly check if the JSON value is 'NULL' prior to casting to a DATE because the
      # JSON_EXTRACT function (or the -> operator) does not convert a JSON null value to a SQL NULL value.
      # See: https://bugs.mysql.com/bug.php?id=85755
      #
      # A solution was added in MySQL 8.0.21 in the form of the JSON_VALUE function, which correctly converts
      # JSON null values into SQL NULL values. However, the lack of support in MySQL 5.7 means we cannot use
      # it because our test suite still uses MySQL 5.7 presumably for backwards compatibility reasons.
      # See: https://dev.mysql.com/doc/refman/8.0/en/json-search-functions.html#function_json-value
      t.virtual :charged_through_date, type: :date, as: "(IF(JSON_TYPE(`payload`->'$.chargedThroughDate')='NULL', NULL, CAST(`payload`->>'$.chargedThroughDate' AS DATE)))"

      t.index [:charged_through_date, :billing_period], name: "idx_on_charged_though_date_and_billing_period"
    end
  end
end
