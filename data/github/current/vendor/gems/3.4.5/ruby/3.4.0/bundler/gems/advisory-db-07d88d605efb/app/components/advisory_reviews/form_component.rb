# frozen_string_literal: true

module AdvisoryReviews
  class FormComponent < ApplicationComponent
    attr_reader :advisory_review, :advisory_payload, :vulnerability_prediction_attributes, :body_version

    delegate :severity_color,
      :severity_label,
      :severities,
      to: :AdvisoryDB

    delegate :read_only?, to: :advisory_review

    def initialize(advisory_review:, advisory_payload:, vulnerability_prediction_attributes: {}, body_version: nil)
      @advisory_review = advisory_review
      @advisory_payload = advisory_payload
      @vulnerability_prediction_attributes = vulnerability_prediction_attributes
      @body_version = body_version || advisory_review.body_version
    end

    def suggestion_source
      link_to("This is an AI based suggestion, please accept or reject it before publishing", "#")
    end
  end
end
