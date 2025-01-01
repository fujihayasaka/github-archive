# typed: true
# frozen_string_literal: true

module GlobalIdMigration
  class Schedule
    def self.run(metadata)
      details = metadata.sort_by { |_pon, deets| deets["ready_date"] }
      report = {}
      report["headers"] = ["Object", "Ready Date",  "Status"]
      report["rows"] = details.map { |k, v| [k, v["ready_date"], v["status"]] }

      report
    end
  end
end
