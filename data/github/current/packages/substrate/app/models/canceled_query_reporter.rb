# typed: true
# frozen_string_literal: true

class CanceledQueryReporter
  include GitHub::Memoizer

  def initialize(sql)
    @sql = sql
  end

  def self.call(sql)
    new(sql).report
  end

  def report
    return unless reporting_enabled?

    GitHub.logger.warn("canceled query", {
      "query_digest": GitHub::SQL::Digester.digest_sql(@sql),
    })
  end

  private

  memoize def reporting_enabled?
    use_percentage = GitHub.environment.fetch("REPORT_CANCELED_QUERY_PERCENTAGE", 0).to_i
    reporting_random_number.between?(0, use_percentage)
  end

  def reporting_random_number
    SecureRandom.random_number(1..100)
  end
end
