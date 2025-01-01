# frozen_string_literal: true

module CVEReviews
  class Rejection
    include ActiveModel::Validations

    attr_reader :reason_template, :reason, :replaced_by

    validates :reason, presence: true
    validates :replaced_by, cve_id: true, presence: true, if: proc { |rejection| rejection.template_duplicate? }

    def initialize(reason_template:, reason:, replaced_by:)
      @reason_template = reason_template
      @reason = reason
      @replaced_by = replaced_by
    end

    def template_duplicate?
      reason_template == "duplicate"
    end
  end
end
