# frozen_string_literal: true

module CVEReviews
  class RejectButtonComponent < ApplicationComponent
    attr_reader :cve_review, :reject_modal_error, :rejection, :show_reject_modal

    def initialize(cve_review:, reject_modal_error: "", rejection: nil, show_reject_modal: false)
      @cve_review = cve_review
      @reject_modal_error = reject_modal_error
      @rejection = rejection.nil? ? CVEReviews::Rejection.new(reason_template: nil, reason: "", replaced_by: "") : rejection
      @show_reject_modal = show_reject_modal
    end

    def reject_comment_template_options
      [
        {
          label: "Invalid",
          text: "Further research determined the issue is not a vulnerability.",
          value: "invalid",
        },
        {
          label: "Duplicate",
          text: "This CVE is a duplicate of another CVE.",
          value: "duplicate",
        },
        {
          label: "Other",
          text: "",
          value: "other",
        },
      ]
    end
  end
end
