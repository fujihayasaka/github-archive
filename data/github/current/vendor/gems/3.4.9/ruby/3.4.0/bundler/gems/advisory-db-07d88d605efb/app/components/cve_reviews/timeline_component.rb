# frozen_string_literal: true

module CVEReviews
  class TimelineComponent < ::TimelineComponent
    private

    def versions
      versions = cve_review.versions.preload(:user).to_a

      cve_review.cve_requests.preload(versions: :user).find_each do |cve_request|
        versions.concat(cve_request.versions)
      end

      cve_review.mitre_cve_submissions.preload(versions: :user).find_each do |mitre_submission|
        versions.concat(mitre_submission.versions)
      end

      advisory = cve_review.advisory_review&.advisory

      if advisory
        versions.concat(advisory.versions.preload(:user).to_a)
      end

      versions.sort_by!(&:id)
    end

    def cve_review
      subject
    end
  end
end
