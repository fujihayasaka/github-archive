# typed: true
# frozen_string_literal: true

# Hydro event subscriptions related to MySQL MAX_EXECUTION_TIME query cancellations.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("mysql.query.canceled") do |payload|
    publish(payload, schema: "github.database.v0.MaxExecutionTime")
  end
end
