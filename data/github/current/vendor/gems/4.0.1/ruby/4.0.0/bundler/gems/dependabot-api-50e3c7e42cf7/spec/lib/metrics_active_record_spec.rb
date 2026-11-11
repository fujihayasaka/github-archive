# frozen_string_literal: true

require "rails_helper"
require "metrics_active_record"

RSpec.describe "ActiveRecord metrics", type: :integration do
  # Warm up the database connection
  before { Account.first }

  it "records query time" do
    expect(MetricsClient).to receive(:increment).with("db_query.count")
    expect(MetricsClient).
      to receive(:timing).with("db_query.time", kind_of(Numeric))

    Account.first
  end
end
