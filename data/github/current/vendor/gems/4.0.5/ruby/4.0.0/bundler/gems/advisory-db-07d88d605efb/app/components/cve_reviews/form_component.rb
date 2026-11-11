# frozen_string_literal: true

module CVEReviews
  class FormComponent < ApplicationComponent
    attr_reader :cve_review, :cve_request, :can_edit_internal, :can_edit_vendor_name_and_product, :expanded_edit_confirm_reference, :expanded_internal, :read_only_form

    delegate :confirm_reference,
      :problemtype_values,
      to: :cve_review
    delegate :description, to: :cve_request, prefix: :current_request

    def initialize(cve_review:, cve_request:, can_edit_confirm_reference: nil, can_edit_internal: nil, can_edit_vendor_name_and_product: false, expanded_edit_confirm_reference: nil, expanded_internal: nil, read_only_form: nil)
      @cve_review = cve_review
      @cve_request = cve_request
      @can_edit_confirm_reference = can_edit_confirm_reference
      @can_edit_internal = can_edit_internal
      @can_edit_vendor_name_and_product = can_edit_vendor_name_and_product
      @expanded_edit_confirm_reference = expanded_edit_confirm_reference
      @expanded_internal = expanded_internal
      @read_only_form = read_only_form
    end

    def cwe_payloads
      problemtype_values.map { |value| CWEPayload.new(value.split(":")[0]) }
    end

    def read_only?
      read_only_form.nil? ? cve_review.read_only? : read_only_form
    end

    def can_edit_confirm_reference?
      if @can_edit_confirm_reference.nil?
        cve_review.repository_advisory_feed_entry.nil? || cve_review.confirm_reference.blank?
      else
        @can_edit_confirm_reference
      end
    end

    def can_edit_internal?
      if can_edit_internal.nil?
        cve_review.ghsl_request.present?
      else
        can_edit_internal
      end
    end

    def expanded_edit_confirm_reference?
      if expanded_edit_confirm_reference.nil?
        cve_review.ghsl_request.present?
      else
        expanded_edit_confirm_reference
      end
    end

    def expanded_internal?
      if expanded_internal.nil?
        cve_review.ghsl_request.present?
      else
        expanded_internal
      end
    end

    def show_confirm_reference_reminder?
      cve_review.persisted? && cve_review.ghsl_request.present? && confirm_reference&.match?(%r{\Ahttps?://securitylab\.github\.com/advisories/?\z})
    end

    def show_ghsl_banner?
      cve_review.persisted? && cve_review.ghsl_request.present? && cve_review.curation_state != "published"
    end
  end
end
