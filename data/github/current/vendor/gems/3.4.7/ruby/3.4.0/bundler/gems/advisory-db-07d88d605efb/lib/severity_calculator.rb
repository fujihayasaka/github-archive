# frozen_string_literal: true

require "cvss_suite"

class SeverityCalculator
  def self.calculate(**args)
    new(**args).severity
  end

  def self.maximum(severities)
    (severities & AdvisoryDB.severities).max_by do |severity|
      AdvisoryDB.severities.index(severity)
    end
  end

  def self.from_cvss_v3(vector_string)
    base_cvss_score = CvssSuite.new(vector_string).overall_score
    calculate(cvss_v3_base_score: base_cvss_score)
  end

  def self.from_cvss_v4(vector_string)
    base_cvss_score = CvssSuite.new(vector_string).overall_score
    calculate(cvss_v4_base_score: base_cvss_score)
  end

  attr_reader :cvss_v2_base_score, :cvss_v3_base_score, :cvss_v4_base_score

  def initialize(cvss_v2_base_score: nil, cvss_v3_base_score: nil, cvss_v4_base_score: nil)
    @cvss_v2_base_score = validate_cvss_base_score(cvss_v2_base_score)
    @cvss_v3_base_score = validate_cvss_base_score(cvss_v3_base_score)
    @cvss_v4_base_score = validate_cvss_base_score(cvss_v4_base_score)
  end

  def severity
    # If CVSS v2 and v3 produce two different severities, we take the most
    # severe of the two.
    # If CVSS v4 is present, prefer that.
    cvss_v4_severity || self.class.maximum([cvss_v2_severity, cvss_v3_severity])
  end

  def cvss_v2_severity
    case cvss_v2_base_score
    when nil   then nil
    when 0...4 then "low"
    when 4...7 then "moderate"
    when 7..10 then "high"
    end
  end

  def cvss_v3_severity
    case cvss_v3_base_score
    when nil   then nil
    when 0...4 then "low"
    when 4...7 then "moderate"
    when 7...9 then "high"
    when 9..10 then "critical"
    end
  end

  def cvss_v4_severity
    case cvss_v4_base_score
    when nil   then nil
    when 0...4 then "low"
    when 4...7 then "moderate"
    when 7...9 then "high"
    when 9..10 then "critical"
    end
  end

  private

  def validate_cvss_base_score(cvss_base_score)
    case cvss_base_score
    when nil
      nil
    when 0..10, /\A0*?(\d(\.\d+)?|10(\.0+)?)\z/ # Any number zero through ten
      cvss_base_score.to_d
    else
      raise ArgumentError, "invalid CVSS base score"
    end
  end
end
