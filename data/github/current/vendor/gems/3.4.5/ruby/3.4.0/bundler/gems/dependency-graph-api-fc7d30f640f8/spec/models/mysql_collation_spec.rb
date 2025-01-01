require "rails_helper"

RSpec.describe ActiveRecord::Base, type: :model do
  subject(:mysql_connection) { described_class.connection }

  context "collation" do
    it "sets connection_collation explicitly" do
      collation = mysql_connection.execute("SELECT @@collation_connection").first.first
      expect(collation).to eq("utf8mb4_general_ci")
    end
  end
end
