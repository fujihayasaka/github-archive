# typed: true
# frozen_string_literal: true

module GitHub::SQLCheckers::TableParser
  # To capture and ignore the edge case of `ON DUPLICATE KEY UPDATE` where
  # there are variable lengths of whitespaces between `KEY` and `UPDATE`,
  # we unfortunately cannot use negative lookbehinds, because Ruby does not
  # support variable length lookbehinds. Instead, we will capture the
  # preceding keyword and check if it contains `KEY` in the next step.
  REGEX = /(\sFROM|\sJOIN|UPDATE|KEY\s+UPDATE|INSERT(?:\s+INTO)?)\s+`?(\w+(?:,\s*\w+)*)`?/im

  def self.run(sql)
    sql.scan(REGEX).flat_map do |keyword, tables|
      next if keyword.end_with?("UPDATE") && keyword.start_with?("KEY")

      if tables.include?(",")
        tables.split(/\s*,\s*/).each(&:strip!)
      else
        tables.strip!
        tables
      end
    end.compact.uniq
  end
end
