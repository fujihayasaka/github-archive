# typed: true
# frozen_string_literal: true

# rubocop:disable Rails/ModuleNaming
class CVEEPSS < ApplicationRecord::Notify
  self.table_name = "cve_epss"

  DESCRIPTION = "The Exploit Prediction Scoring System"
  CVE_EXPLOITATION_DESCRIPTION = "CVE exploitation likelihood"
  PERCENTAGE_SHORT_DESCRIPTION = "the likelihood of a CVE being exploited"
  PERCENTAGE_DESCRIPTION = "The EPSS percentage represents #{PERCENTAGE_SHORT_DESCRIPTION}."
  PERCENTILE_SHORT_DESCRIPTION = "the relative rank of the CVE's likelihood of being exploited compared to other CVEs"
  PERCENTILE_DESCRIPTION = "The EPSS percentile represents #{PERCENTILE_SHORT_DESCRIPTION}."
  EPSS_FIELDS = {
    "epss_percentage" => "percentage",
    "epss_percentile" => "percentile"
  }
  EMPTY_PARSED_QUERY = {}.freeze
  VALID_SCORE_RANGE = (0.0..1.0).freeze

  # Query qualifiers for the epss_percentage and epss_percentile fields:
  # n	    epss_percentage:1         match scores exactly equal to 1.
  # >[=]n	epss_percentile:>=0.3     match scores greater than or equal to 0.3.
  # <[=]n epss_percentage:<0.50     match scores less than 0.50.
  # n..n 	epss_percentile:0.05..1.0 match scores between (inclusive) 0.05 and 1.0.
  QUERY_QUALIFIER_REGEX = %r{
    \A(
      (?<range>                     # Look for a range type query
        (?<start>\d*\.\d+|\d+)      # First number (allows ".3" or "0.3")
        \.\.                        # Range separator
        (?<end>\d*\.\d+|\d+)        # Second number
      )
    |                               # The two types of queries are mutually exclusive
      (?<comparison>                # Look for a comparison type query
        (?<operator>[<>]=?)?        # Optional comparison operator
        (?<number>\d*\.\d+|\d+)     # Number to compare (allows ".3" or "0.3")
      )
    )\z
  }x.freeze

  validates :cve_id, presence: true, length: { maximum: 20 }, uniqueness: true
  validates :percentage, presence: true, numericality: { in: VALID_SCORE_RANGE }
  validates :percentile, presence: true, numericality: { in: VALID_SCORE_RANGE }
  validates :calculation_date, presence: true
  after_commit :synchronize_search_index

  belongs_to :vulnerability, class_name: "Vulnerability", foreign_key: :cve_id, primary_key: :cve_id, inverse_of: :cve_epss

  def percentage=(value)
    write_attribute(:percentage, value.to_f) if value.present?
  end

  def percentile=(value)
    write_attribute(:percentile, value.to_f) if value.present?
  end

  def synchronize_search_index
    unless GitHub.single_tenant_enterprise?
      v = vulnerability
      v.synchronize_search_index if v.present?
    end
  end

  # Parse EPSS query qualifiers into hash objects. It expects that the qualifier value has already been split from the
  # qualifier token. It returns a hash with keys that indicate if it was a comparison or range query, or an empty hash
  # if the qualifier is invalid. This method can be used to parse both percentage and percentile qualifiers.
  def self.parse_query_qualifier(qualifier)
    return EMPTY_PARSED_QUERY unless qualifier.present?

    matches = qualifier.match(QUERY_QUALIFIER_REGEX)
    return EMPTY_PARSED_QUERY if matches.nil?

    if matches[:range]
      { range: true, start: matches[:start].to_f, end: matches[:end].to_f }
    elsif matches[:comparison]
      { comparison: true, operator: (matches[:operator] || "=").to_sym, number: matches[:number].to_f }
    else
      EMPTY_PARSED_QUERY
    end
  end

  # Check if an EPSS query qualifier is valid. It expects that the qualifier value has already been split from the
  # qualifier token. It returns true if the qualifier is valid, false otherwise. This method can be used to validate
  # both percentage and percentile qualifiers.
  def self.valid_query_qualifier?(qualifier)
    parsed_qualifier = parse_query_qualifier(qualifier)

    if parsed_qualifier[:range]
      return false if parsed_qualifier[:start] >= parsed_qualifier[:end]
      return false unless VALID_SCORE_RANGE.include?(parsed_qualifier[:start])
      return false unless VALID_SCORE_RANGE.include?(parsed_qualifier[:end])
      true
    elsif parsed_qualifier[:comparison]
      return false unless VALID_SCORE_RANGE.include?(parsed_qualifier[:number])
      true
    else
      false
    end
  end
end
# rubocop:disable Rails/ModuleNaming
