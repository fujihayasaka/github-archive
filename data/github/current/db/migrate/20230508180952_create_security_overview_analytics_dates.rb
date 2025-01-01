# typed: true
# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class CreateSecurityOverviewAnalyticsDates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::SecurityOverviewAnalytics)

  def change
    create_table :soa_dates, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # The primary key in this table is a surrogate key containing integer representation of the date_value
      # For example for 2023-06-07 the surrogate key is 20230607
      # The linter is disabled for this reason, as the primary key is not auto_increment and is limited to valid dates
      # which all fit in int type
      t.column :id, :int, primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.date :date_value, null: false
    end
  end
end
