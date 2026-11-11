# typed: true
# frozen_string_literal: true

module GlobalIdMigration
  class ResultPrinter
    def self.print(results, formatter: GlobalIdMigration::Formatting::Json)
      new(results, formatter: formatter).print
    end

    def initialize(results, formatter:)
      @formatter = formatter.new(results)
    end

    def print
      puts @formatter.format
    end
  end
end
