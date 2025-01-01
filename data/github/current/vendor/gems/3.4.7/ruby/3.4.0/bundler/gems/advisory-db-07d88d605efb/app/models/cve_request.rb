# frozen_string_literal: true

require "github/encoding"
require "normal_yaml"

# a CVE request is sent from a repository advisory when the maintainer
# publishes the advisory
# it records all the info sent in the request
# the actual decision about whether to issue a CVE or not is made in CVEReview
class CVERequest < ApplicationRecord
  belongs_to :cve_review,
    primary_key: :ghsa_id,
    foreign_key: :ghsa_id,
    optional: true, # requests get saved before reviews are made
    inverse_of: :cve_requests

  enum :severity, AdvisoryDB.severities

  serialize :cwe_ids, coder: NormalYAML
  serialize :affected_products_payload, coder: NormalYAML

  validates :affected_products_payload, affected_products_payload: true

  # for fields that come directly from user input, ensure we are handling utf-8 properly
  extend ::GitHub::Encoding
  force_utf8_encoding(
    :title,
    :description,
    :cwe_ids,
    :cvss_v3,
    :cvss_v4,
    :affected_products_payload,
  )

  def repo_name_with_owner
    advisory_permalink.match(%r{\Ahttps://github\.com/([^/]+/[^/]+)/})[1]
  end

  def repo_owner
    repo_name_with_owner.split("/")[0]
  end

  def repo_name
    repo_name_with_owner.split("/")[1]
  end
end
