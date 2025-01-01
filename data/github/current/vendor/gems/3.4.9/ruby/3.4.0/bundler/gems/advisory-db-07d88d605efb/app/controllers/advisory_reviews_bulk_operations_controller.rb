# frozen_string_literal: true

class AdvisoryReviewsBulkOperationsController < InboxController
  def bulk_assignment
    error_hash = {}
    # Normally, we would guard and 400 this type of operation,
    # ensuring we don't log it to Failbot or w/e. however, this is an internal tool
    # and any failures are of our own devising.
    # The expected request format is:
    # {
    #   "ghsaIds": "GHSA-XXX,GHSA-YYY,GHSA-ZZZ",
    #   "assignTo": "brphelps"
    #   "assignToSlot": "1"
    # }
    # It is also possible to not submit assignTo, which should unassign all curators.
    # assignToSlot must be specified, and targets either the first or second approval.
    # If the slot is filled, we update it. If it's not, we create a new approval.
    request_body_json = JSON.parse(request.body.read)
    assign_to_param = request_body_json["assignTo"]
    assign_to_slot = request_body_json["assignToSlot"]
    unless ["1", "2"].include? assign_to_slot
      payload = {
        error: "Slot must be specified as either 1 or 2.",
        status: 400,
      }
      render json: payload, status: :bad_request
      return
    end
    assignment_target = assign_to_param.nil? ? nil : User.find_by!(login: assign_to_param)
    all_advisories_to_assign = request_body_json["ghsaIds"].split(",")
    advisory_reviews = AdvisoryReview.includes(:approvals).where(ghsa_id: all_advisories_to_assign)

    advisory_reviews.each do |advisory_review|
      first_approval = advisory_review.approvals.first
      second_approval = advisory_review.approvals.second

      if assign_to_slot == "1" && first_approval
        if assignment_target.nil?
          first_approval.delete
        else
          first_approval.update!(user_id: assignment_target.id)
        end
      elsif assign_to_slot == "2" && second_approval
        if assignment_target.nil?
          second_approval.delete
        else
          second_approval.update!(user_id: assignment_target.id)
        end
      elsif assignment_target
        advisory_review.approvals.create!(user_id: assignment_target.id)
      end
    rescue StandardError => error
      error_hash[advisory_review.ghsa_id] = "The advisory review for #{advisory_review.ghsa_id} could not be assigned. Extended error information is:\n#{error}"
      Failbot.report!(error, { context: "Individual assignment operation failed for advisory review #{advisory_review.ghsa_id}" })
    end

    render json: { errorHash: error_hash }
  end

  def bulk_ecosystem_and_package_name
    error_hash = {}
    # Normally, we would guard and 400 this type of operation,
    # ensuring we don't log it to Failbot or w/e. however, this is an internal tool
    # and any failures are of our own devising.
    # The expected request format is:
    # {
    #   "ghsaIds": "GHSA-XXX,GHSA-YYY,GHSA-ZZZ",
    #   "ecosystem": "npm",
    #   "packageName": "lodash"
    # }
    # It is also possible to not submit packageName, which will not edit package name at all.
    request_body_json = JSON.parse(request.body.read)
    ecosystem = request_body_json["ecosystem"]
    package_name = request_body_json["packageName"]
    if ecosystem.blank?
      payload = {
        error: "Ecosystem must be specified, you supplied '#{ecosystem}'.",
        status: 400,
      }
      render json: payload, status: :bad_request
      return
    end

    all_advisories_to_assign = request_body_json["ghsaIds"].split(",")
    advisory_reviews = AdvisoryReview.where(ghsa_id: all_advisories_to_assign)

    advisory_reviews.each do |advisory_review|
      vulns = advisory_review.vulnerabilities
      matching_vulnerability_for_ecosystem = vulns.values.find { |vulnerability| vulnerability["ecosystem"] == ecosystem }
      if !matching_vulnerability_for_ecosystem
        # Get an integer we know is unused.
        key = vulns.keys.present? ? vulns.keys.max + 1 : 0
        vulns[key] = { "ecosystem" => ecosystem, "package_name" => package_name }
        advisory_review.advisory_payload["vulnerabilities"] = vulns
        advisory_review.save!
      elsif !matching_vulnerability_for_ecosystem["package_name"]
        matching_vulnerability_for_ecosystem["package_name"] = package_name
        advisory_review.advisory_payload["vulnerabilities"] = vulns
        advisory_review.save!
      end
    rescue StandardError => error
      error_hash[advisory_review.ghsa_id] = "The advisory review for #{advisory_review.ghsa_id} could not have ecosystem or package name set. Extended error information is:\n#{error}"
      Failbot.report!(error, { context: "Individual ecosystem / packageName operation failed for advisory review #{advisory_review.ghsa_id}" })
    end

    render json: { errorHash: error_hash }
  end

  def bulk_close
    error_hash = {}
    # Normally, we would guard and 400 this type of operation,
    # ensuring we don't log it to Failbot or w/e. however, this is an internal tool
    # and any failures are of our own devising.
    # The expected request format is:
    # { "ghsaIds": "GHSA-XXX,GHSA-YYY,GHSA-ZZZ"}
    request_body_json = JSON.parse(request.body.read)
    all_advisories_to_close = request_body_json["ghsaIds"].split(",")
    advisory_reviews = AdvisoryReview.where(ghsa_id: all_advisories_to_close)

    advisory_reviews.each do |advisory_review|
      if advisory_review.may_revert?
        advisory_review.revert!
      elsif advisory_review.may_reject?
        advisory_review.reject!
      else
        error_hash[advisory_review.ghsa_id] = "Advisory review #{advisory_review.ghsa_id} could not be closed or reverted because it is not allowed (advisory review may be closed already or not pass other validation)."
      end
    rescue StandardError => error
      error_hash[advisory_review.ghsa_id] = "The advisory review for #{advisory_review.ghsa_id} could not be closed. Extended error information is:\n#{error}"
      Failbot.report!(error, { context: "Individual bulk close operation failed for advisory review #{advisory_review.ghsa_id}" })
    end

    render json: { errorHash: error_hash }
  end

  def bulk_label_options
    # The expected request format is:
    # { "ghsaIds": "GHSA-XXX,GHSA-YYY,GHSA-ZZZ"}
    request_body_json = JSON.parse(request.body.read)
    ghsa_ids = request_body_json["ghsaIds"].split(",")
    render partial: "labels/label_options", locals: { advisory_reviews: ghsa_ids.map { |ghsa_id| AdvisoryReview.find_by(ghsa_id: ghsa_id) } }
  end

  def bulk_labels
    error_hash = {}
    # Normally, we would guard and 400 this type of operation,
    # ensuring we don't log it to Failbot or w/e. however, this is an internal tool
    # and any failures are of our own devising.
    # The expected request format is:
    # {
    #   "ghsaIds": "GHSA-XXX,GHSA-YYY,GHSA-ZZZ",
    #   "labelIds": "1,2,3"
    # }
    request_body_json = JSON.parse(request.body.read)
    ghsa_ids = request_body_json["ghsaIds"].split(",")
    advisories_to_label = AdvisoryReview.preload(:labels).where(ghsa_id: ghsa_ids)
    labels_to_assign = Label.where(id: request_body_json["labelIds"].split(","))
    labels_to_unassign = advisories_to_label.map(&:labels).inject(:&) - labels_to_assign

    advisories_to_label.each do |advisory_review|
      advisory_review.labels = (advisory_review.labels + labels_to_assign - labels_to_unassign).uniq
    rescue StandardError => error
      error_hash[advisory_review.ghsa_id] = "The advisory review for #{advisory_review.ghsa_id} failed to update labels. Extended error information is:\n#{error}"
      Failbot.report!(error, { context: "Individual bulk label operation failed for advisory review #{advisory_review.ghsa_id}" })
    end

    render json: { errorHash: error_hash }
  end
end
