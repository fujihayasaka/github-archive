# frozen_string_literal: true

module CVEReviews
  class SidebarComponent < ApplicationComponent
    attr_reader :cve_review, :cve_request, :reject_modal_error, :rejection, :show_reject_modal

    delegate :advisory,
      :assigned_cve_id,
      :ghsa_id,
      :product,
      :vendor_name,
      to: :cve_review

    delegate :severity,
      to: :cve_request

    def initialize(cve_review:, cve_request:, reject_modal_error: "", rejection: nil, show_reject_modal: false)
      @cve_review = cve_review
      @cve_request = cve_request
      @reject_modal_error = reject_modal_error
      @rejection = rejection
      @show_reject_modal = show_reject_modal
    end

    def show_reopen_button?
      cve_review.may_reopen?
    end

    def show_update_button?
      !cve_review.read_only?
    end

    def show_publish_button?
      cve_review.may_submit_to_mitre?
    end

    def show_cve_review_buttons?
      show_update_button? || show_reopen_button? || show_external_action_buttons?
    end

    def show_external_action_buttons?
      show_publish_button? || show_reject_button?
    end

    def show_checks?
      checks.any?
    end

    def show_reject_button?
      AdvisoryDB::Features.enabled?("advisory_db_cve_reviews_reject_published") && cve_review.may_reject?
    end

    def checks_passed?
      return @checks_passed if defined? @checks_passed

      @checks_passed = CheckSuiteRunner.checks_passed?(review: cve_review)
    end

    def checks
      @checks ||= CheckSuiteRunner.get_checks(review: cve_review)
    end

    def mitre_cve_submission
      cve_review.mitre_cve_submissions.last
    end

    def pull_request_number
      mitre_cve_submission.pull_request_url.split("/").last
    end

    # CVERequest now supports multiple affected products, but we currently only
    # show the first one in the sidebar. This could be updated in the future
    # if the information for the remaining elements in the array is desired.
    def affected_versions
      cve_request.affected_products_payload&.first&.dig("affected_versions")
    end

    def ecosystem
      cve_request.affected_products_payload&.first&.dig("ecosystem")
    end

    def package
      cve_request.affected_products_payload&.first&.dig("package")
    end

    def patches
      cve_request.affected_products_payload&.first&.dig("patches")
    end

    def show_related_reviews?
      related_cve_reviews.any?
    end

    def related_cve_reviews
      @related_cve_reviews ||= cve_review.related_cve_reviews.preload(:advisory_review)
    end

    def cve_record_url
      "#{AdvisoryDB.cve_services_api_url}/api/cve/#{assigned_cve_id}"
    end
  end
end
