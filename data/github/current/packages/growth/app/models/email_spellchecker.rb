# typed: true
# frozen_string_literal: true

class EmailSpellchecker
  COMMON_DOMAINS = %w(
    gmail.com
    qq.com
    hotmail.com
    outlook.com
    163.com
    yahoo.com
  ).freeze

  attr_reader :local_part, :domain

  def initialize(email)
    parts = email.split("@")

    if parts.count == 2
      @local_part = parts.first
      @domain = parts.last.downcase
    end
  end

  def self.suggestion_for(email)
    new(email).suggestion
  end

  def suggestion
    return unless local_part && domain
    return if COMMON_DOMAINS.include?(domain)

    suggested_domain = COMMON_DOMAINS.find do |common_domain|
      Levenshtein.distance(common_domain, domain) == 1
    end

    "#{local_part}@#{suggested_domain}" if suggested_domain
  end
end
