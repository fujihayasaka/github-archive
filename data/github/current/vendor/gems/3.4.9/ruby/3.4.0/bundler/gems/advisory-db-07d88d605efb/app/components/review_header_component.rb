# frozen_string_literal: true

class ReviewHeaderComponent < ApplicationComponent
  READ_ONLY_TITLES = {
    not_triaged: "This review must be triaged first.",
    advisory_published: "This review has been published. Reopen to edit.",
    cve_published: "This review has already been published to MITRE.",
    no_cve_id: "This review did not receive a CVE ID.",
    closed: "This review is closed.",
  }.freeze

  include HasCurationState

  attr_reader :review

  delegate :created_at,
    :curation_state,
    :read_only?,
    :title,
    :updated_at,
    to: :review

  def initialize(review:)
    @review = review
  end

  def read_only_title
    READ_ONLY_TITLES[review.read_only_reason] || ""
  end
end
