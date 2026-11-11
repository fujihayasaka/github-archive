# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :primary, reading: :primary, readreplica: :readreplica }

  has_paper_trail versions: { class_name: "ApplicationVersion" }

  # Used to search for a substring in a specific column
  # From dotcom: lib/like_query.rb and config/initializers/active_record_sanitize_sql_like.rb
  def self.with_substring(column, substring)
    sanitized_substring = substring.gsub(/[\\_%]/) { |x| ["\\", x].join }
    where("#{column} LIKE ?", "%#{sanitized_substring}%")
  end
end
