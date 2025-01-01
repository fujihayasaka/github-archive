# frozen_string_literal: true

module NPMIDExtractor
  NPM_ADVISORY_REFERENCE_PATTERN = %r{npmjs\.com/advisories/(?<npm_id>\d+)}
  NODESECURITY_IO_REFERENCE_PATTERN = %r{nodesecurity\.io/advisories/(?<npm_id>\d+)}

  ALL_PATTERNS = [
    NPM_ADVISORY_REFERENCE_PATTERN,
    NODESECURITY_IO_REFERENCE_PATTERN,
  ].freeze

  # extract an NPM ID from a single URL
  def self.extract_npm_id_from_reference(url)
    raise ArgumentError unless url.is_a?(String)

    ALL_PATTERNS.each do |url_pattern|
      match_data = url_pattern.match(url)
      return match_data[:npm_id].to_i if match_data
    end

    nil
  end

  def self.extract_npm_id_from_reference_list(urls)
    raise ArgumentError unless urls.is_a?(Array)

    urls.each do |url|
      id = extract_npm_id_from_reference(url)
      return id if id
    end

    nil
  end

  def self.extract(advisory_or_review)
    case advisory_or_review
    when Advisory
      urls = advisory_or_review.references.pluck(:url)
      extract_npm_id_from_reference_list(urls)
    when AdvisoryReview
      extract_npm_id_from_reference_list(advisory_or_review.advisory_payload["references"])
    end
  end
end
