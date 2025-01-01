# frozen_string_literal: true

class AdvisoryReviewsController < InboxController
  around_action :not_found_to_404, only: [:timeline, :diff, :show]
  before_action :require_passing_checks, only: [:approve, :publish, :withdraw]
  before_action :record_curation_decision, only: [:close, :approve, :publish, :withdraw, :revert]

  include StaleModelDetection

  def index; end

  def new
    render locals: {
      advisory_review: AdvisoryReview.new(advisory_payload: {}),
      advisory_payload: AdvisoryPayload.new(data: {}),
    }
  end

  def show
    CheckSuiteRunner.run_checks(review: advisory_review)

    vulnerability_predictions = advisory_review.ai_predictions.pending if AdvisoryDB::Features.enabled?("gpt4_prediction")
    vulnerability_prediction_attributes = normalized_vulnerability_prediction_attributes(vulnerability_predictions)
    render locals: {
      advisory_review: advisory_review,
      vulnerability_prediction_attributes: vulnerability_prediction_attributes,
    }
  end

  def timeline
    render locals: { advisory_review: advisory_review }
  end

  def diff
    diff = Publisher.new(advisory_review).diff

    render locals: { advisory_review: advisory_review, diff: diff }
  end

  def create
    advisory_review = AdvisoryReview.build_blank
    advisory_payload = AdvisoryPayload.new(data: advisory_payload_params)
    advisory_review.assign_attributes(advisory_review_params)

    # Ensure both models populate errors
    advisory_review_valid = advisory_review.valid?
    advisory_payload_valid = advisory_payload.valid?

    if advisory_review_valid && advisory_payload_valid
      if advisory_payload.data["cvss_v4"].present?
        advisory_payload.data["severity"] = SeverityCalculator.from_cvss_v4(advisory_payload.data["cvss_v4"])
      elsif advisory_payload.data["cvss_v3"].present? && advisory_review.advisory_payload["cvss_v4"].blank?
        advisory_payload.data["severity"] = SeverityCalculator.from_cvss_v4(advisory_payload.data["cvss_v3"])
      end

      advisory_review.update!(advisory_payload: advisory_payload.data)
      advisory_review.notify_user_saved_event(current_user)

      redirect_to advisory_review,
        notice: "Advisory review #{advisory_review.ghsa_id} was created successfully!"
    else
      render action: :new, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
        advisory_payload: advisory_payload,
      }
    end
  end

  def update
    advisory_payload = AdvisoryPayload.new(data: advisory_payload_params)
    advisory_review.assign_attributes(advisory_review_params)

    # Ensure both models populate errors
    advisory_review_valid = advisory_review.valid?
    advisory_payload_valid = advisory_payload.valid?

    if advisory_review.read_only?
      flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be saved because it is read-only!"
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
        body_version: request.params[:body_version],
      }
    elsif stale_model?(advisory_review)
      flash.now[:alert] = "The Advisory review you are editing has changed. Please copy your edits and refresh the page."
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
        advisory_payload: advisory_payload,
        body_version: request.params[:body_version],
      }
    elsif advisory_review_valid && advisory_payload_valid
      advisory_payload.data["vulnerabilities"].each_value do |value|
        next unless value.key?("fix_commits")

        value["fix_commits"].each do |commit|
          next if commit.blank?

          advisory_payload.references << commit
        end
      end

      advisory_payload.references.uniq!

      if advisory_payload.data["cvss_v4"].present?
        advisory_payload.data["severity"] = SeverityCalculator.from_cvss_v4(advisory_payload.data["cvss_v4"])
      elsif advisory_payload.data["cvss_v3"].present? && advisory_review.advisory_payload["cvss_v4"].blank?
        advisory_payload.data["severity"] = SeverityCalculator.from_cvss_v4(advisory_payload.data["cvss_v3"])
      end

      advisory_review.update!(advisory_payload: advisory_payload.data)
      advisory_review.notify_user_saved_event(current_user)
      advisory_review.start_review! if advisory_review.may_start_review?
      process_vulnerability_predictions(advisory_payload)

      redirect_to advisory_review,
        notice: "Advisory review #{advisory_review.ghsa_id} was updated successfully!"
    else
      vulnerability_prediction_attributes = normalized_vulnerability_prediction_attributes(vulnerability_prediction_params)
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
        advisory_payload: advisory_payload,
        vulnerability_prediction_attributes: vulnerability_prediction_attributes,
      }
    end
  end

  def close
    if advisory_review.may_reject?
      advisory_review.reject!

      redirect_to advisory_review,
        notice: "Advisory review #{advisory_review.ghsa_id} was closed successfully!"
    else
      flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be closed!"
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
      }
    end
  end

  def reopen
    if reopen_advisory_review
      redirect_to advisory_review,
        notice: "Advisory review #{advisory_review.ghsa_id} was reopened successfully!"
    else
      flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be reopened!"
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
      }
    end
  end

  def approve
    AdvisoryReview.transaction do
      if params[:approval_type] == "withdraw"
        # Withdrawing restarts the approval flow, so we need to clear the `approved_at`
        # timestamps on the previous approvals
        advisory_review.approvals.each do |approval|
          approval.update(approved_at: nil)
        end
      end

      advisory_review.record_approval(current_user.id)

      case params[:approval_type]
      when "publish"
        advisory_review.approve_to_publish!
      when "withdraw"
        advisory_review.approve_to_withdraw!
      end
    end

    redirect_to advisory_review,
      notice: "Advisory review #{advisory_review.ghsa_id} was approved to #{params[:approval_type]}!"
  rescue StandardError => error
    flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be approved! An error occurred."
    Failbot.report!(error, { ghsa_id: advisory_review.ghsa_id })
    render action: :show, status: :unprocessable_entity, locals: {
      advisory_review: advisory_review,
    }
  end

  def publish
    if advisory_review.may_accept?
      Publisher.new(advisory_review).publish(approve_as_user: current_user.id)

      redirect_to advisory_review,
        notice: "Advisory review #{advisory_review.ghsa_id} was published successfully!"
    else
      flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be published!"

      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
      }
    end
  rescue StandardError => error
    flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be published! An error occurred."
    Failbot.report!(error, { ghsa_id: advisory_review.ghsa_id })
    render action: :show, status: :unprocessable_entity, locals: {
      advisory_review: advisory_review,
    }
  end

  def withdraw
    if advisory_review.may_withdraw?
      Publisher.new(advisory_review).publish(approve_as_user: current_user.id, withdraw_advisory_review: true)

      redirect_to advisory_review,
        notice: "Advisory review #{advisory_review.ghsa_id} was withdrawn successfully!"
    else
      flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} is not withdrawable!"
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
      }
    end
  rescue StandardError => error
    flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be withdrawn! An error occurred."
    Failbot.report!(error, { ghsa_id: advisory_review.ghsa_id })
    render action: :show, status: :unprocessable_entity, locals: {
      advisory_review: advisory_review,
    }
  end

  def revert
    if advisory_review.may_revert?
      advisory_review.revert!

      redirect_to advisory_review,
        notice: "Advisory review #{advisory_review.ghsa_id} was reverted successfully!"
    else
      flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not be reverted!"
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
      }
    end
  end

  def set_labels
    labels = Label.where(id: params[:labels])
    advisory_review.labels = labels
    redirect_to advisory_review,
      notice: "Advisory review #{advisory_review.ghsa_id} labels were set!"
  rescue StandardError => error
    flash.now[:alert] = "Advisory review #{advisory_review.ghsa_id} could not set labels! An error occurred."
    Failbot.report!(error, { ghsa_id: advisory_review.ghsa_id })
    render action: :show, status: :unprocessable_entity, locals: {
      advisory_review: advisory_review,
    }
  end

  private

  def advisory_review
    return @advisory_review if defined? @advisory_review

    @advisory_review = AdvisoryReview.find_by!(ghsa_id: params.require(:ghsa_id))
  end

  def require_passing_checks
    CheckSuiteRunner.run_checks(review: advisory_review)

    unless CheckSuiteRunner.checks_passed?(review: advisory_review)
      flash.now[:alert] = "Could not #{params[:action]} advisory review #{advisory_review.ghsa_id}! All checks must pass."
      render action: :show, status: :unprocessable_entity, locals: {
        advisory_review: advisory_review,
      }
    end
  end

  def reopen_advisory_review
    if advisory_review.may_restart_review?
      advisory_review.restart_review!
    elsif advisory_review.may_revisit?
      advisory_review.revisit!
    else
      false
    end
  end

  def process_vulnerability_predictions(advisory_payload)
    predictions = vulnerability_prediction_params
    return unless predictions

    vulnerabilities = advisory_payload.vulnerability_payloads
    predictions.each do |id, prediction_params|
      prediction = advisory_review.ai_predictions.find_by(id: id) if AdvisoryDB::Features.enabled?("gpt4_prediction")
      next unless prediction

      case prediction_params[:decision]
      when "accepted"
        vulnerability_index = prediction_params[:vulnerability_index]
        accepted_payload = nil
        if /\A\d+\z/.match?(vulnerability_index)
          vulnerability_payload = vulnerabilities[vulnerability_index.to_i]&.data
          if vulnerability_payload
            accepted_payload = {
              package_ecosystem: vulnerability_payload["ecosystem"],
              package_name: vulnerability_payload["package_name"],
              vulnerable_version_range: vulnerability_payload["vulnerable_version_range"],
              first_patched_version: vulnerability_payload["first_patched_version"],
            }
          end
        end
        prediction.accept!(accepted_payload)
      when "rejected"
        prediction.reject!
      end
    end
  end

  def advisory_review_params
    params.require(:advisory_review).permit(:review_notes, :cve_id)
  end

  def advisory_payload_params
    params
      .require(:advisory_review)
      .require(:advisory_payload)
      .permit(
        :cvss_v3,
        :cvss_v4,
        :description,
        :severity,
        :source_code_location,
        :summary,
        :withdrawn,
        cwe_ids: [],
        references: [],
        vulnerabilities: [
          :ecosystem,
          :first_patched_version,
          :package_name,
          :vulnerable_version_range,
          :withdrawn,
          { fix_commits: [] },
        ],
      )
  end

  def vulnerability_prediction_params
    params
      .require(:advisory_review)
      .permit(vulnerability_predictions: [
        :ecosystem,
        :first_patched_version,
        :package_name,
        :vulnerable_version_range,
        :decision,
        :vulnerability_index,
      ])[:vulnerability_predictions]
  end

  # Unlike advisory payloads which are always hashes, predictions can either
  # come from the database or from form params after submitting. This helper
  # method normalizes both cases to hashes that look close-enough for our view
  # components.
  def normalized_vulnerability_prediction_attributes(vulnerability_predictions)
    # In case there were no vulnerability_predictions params submitted
    return [] if vulnerability_predictions.nil?

    case vulnerability_predictions
    when ActiveRecord::AssociationRelation
      vulnerability_predictions.map(&:attributes)
    when ActionController::Parameters
      # Convert the `"id" => { form_params }` format of the params hash to an
      # array of attributes that includes the id
      vulnerability_predictions.to_h.map do |id, params|
        params["id"] = id
        params
      end
    else
      # Guard against Rails API changes since we're checking Rails class names
      klass = vulnerability_predictions.class.name
      raise ArgumentError, "Unsupported type #{klass}"
    end
  end

  def record_curation_decision
    type = if advisory_review.approved_to_publish? || advisory_review.approved_to_withdraw?
             "advisory_publication"
           elsif advisory_review.reviewed_advisory?
             "advisory_update"
           else
             "advisory_review"
           end

    decision = case params[:action]
               when "revert"
                 "close"
               when "approve"
                 "ready_to_#{params[:approval_type]}"
               else
                 params[:action]
               end

    advisory_review.record_curation_decision(type: type, decision: decision, curator: current_user.login)
  end

  def not_found_to_404
    yield
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
