# frozen_string_literal: true

class CVEReviewsController < InboxController
  RejectPublishedError = Class.new(StandardError)
  UnpublishableError = Class.new(StandardError)

  def index; end

  def create
    @cve_request = CVERequest.new(cve_request_params)
    @cve_review = CVEReview.new(**cve_review_params, ghsa_id: @cve_request.ghsa_id, state: :notified)
    @cve_review.build_ghsl_request(ghsl_request_params)

    begin
      ActiveRecord::Base.transaction do
        # must have a title otherwise empty string appears in cve review index table
        raise(StandardError, "Title cannot be blank") if cve_review.title.blank?

        @cve_request.save!
        @cve_review.save!
        @cve_review.ghsl_request.save!
        assign_cve!(@cve_review)
      end
    rescue StandardError => error
      flash.now[:alert] = "CVE review could not be created: #{error.message}"
      render action: :new, status: :unprocessable_entity
      return
    end

    # unlike open cve review triage, here do not need to notify repository
    # advisory with publish_to_hydro, so just do this:
    cve_review.import_related_advisory

    redirect_to @cve_review, notice: "CVE review was created successfully!"
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  def new
    @cve_request = CVERequest.new
    @cve_review = CVEReview.new
  end

  def show
    CheckSuiteRunner.run_checks(review: cve_review)

    render locals: {
      cve_review: cve_review,
      cve_request: cve_review.current_cve_request,
    }
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def timeline
    render locals: { cve_review: cve_review }
  end

  def update
    cve_review.assign_attributes(cve_review_params)

    if cve_review_params[:cvss_vectorString].present? && cve_review_params[:cvss_vectorString].starts_with?("CVSS:4.0/")
      cve_review.cvss_v4 = cve_review_params[:cvss_vectorString]
    end

    # Convert all newlines (including carriage returns) into standard newlines.
    # We receive descriptions with carriage returns from textarea form fields,
    # which make YAML diffs difficult to read.
    cve_review.description&.gsub!(/\R/, "\n")

    # Remove any blank references or version values before saving
    cve_review.misc_references.compact_blank!
    cve_review.version_values.compact_blank!

    if cve_review.read_only?
      flash.now[:alert] = "CVE review #{cve_review.ghsa_id} could not be saved because it is read-only!"
      render action: :show, status: :unprocessable_entity, locals: {
        cve_review: cve_review,
        cve_request: cve_review.current_cve_request,
      }
    elsif cve_review.valid?
      cve_review.save!
      cve_review.ghsl_request&.update!(ghsl_request_params)
      redirect_to cve_review,
        notice: "CVE review #{cve_review.ghsa_id} was updated successfully!"
    else
      flash.now[:alert] = "CVE review #{cve_review.ghsa_id} could not be saved!"
      render action: :show, status: :unprocessable_entity, locals: {
        cve_review: cve_review,
        cve_request: cve_review.current_cve_request,
      }
    end
  end

  def publish
    # Do not record a curation decision on a CVE review if one already exists. This means that a decision
    # on the CVE has already been made and this is just an update sent to MITRE.
    unless MITRECVESubmission.find_by(ghsa_id: cve_review.ghsa_id)
      record_curation_decision
    end

    if !cve_review.may_submit_to_mitre? || !checks_passed_for_cve_review?
      raise UnpublishableError, "Ensure it is in an open curation state and that checks pass"
    end

    MITRECVESubmission.record_cve_submission(
      cve_review: cve_review,
      pull_request_url: params.require(:pull_request_url),
    )
    redirect_to cve_review,
      notice: "CVE review #{cve_review.ghsa_id} was published successfully!"
  rescue ActiveRecord::RecordNotFound
    render_404
  rescue AASM::InvalidTransition, ActionController::ParameterMissing, ActiveModel::ValidationError, CVEAPI::Client::CVEAPIClientError, UnpublishableError => error
    render_show_unprocessable_entity(error)
  rescue StandardError => error
    Failbot.report!(error, { ghsa_id: cve_review.ghsa_id })
    render_show_unprocessable_entity(error)
  end

  def reject
    unless AdvisoryDB::Features.enabled?("advisory_db_cve_reviews_reject_published")
      render_404
      return
    end

    unless cve_review.may_reject?
      raise RejectPublishedError, "A CVE Review can only be rejected after being submitted"
    end

    cve_reviews_rejection.validate!

    MITRECVESubmission.record_cve_rejection(cve_review: cve_review, rejection_params: rejection_params)

    redirect_to cve_review
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue AASM::InvalidTransition, ActionController::ParameterMissing, CVEAPI::Client::CVEAPIClientError, RejectPublishedError, ActiveModel::ValidationError => error
    render action: :show, status: :unprocessable_entity, locals: {
      cve_review: cve_review,
      cve_request: cve_review.current_cve_request,
      reject_modal_error: error.message,
      rejection: cve_reviews_rejection,
      show_reject_modal: true,
    }
  end

  def reopen
    if cve_review.may_reopen?
      cve_review.reopen!
      redirect_to cve_review, notice: "CVE review #{cve_review.ghsa_id} was reopened successfully!"
    else
      flash[:alert] = "CVE Review is not in a state that can be reopened"
      render action: :show, status: :unprocessable_entity, locals: {
        cve_review: cve_review,
        cve_request: cve_review.current_cve_request,
      }
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  private

  def assign_cve!(cve_review)
    available_cve_id = CVE.first_available_cve_id_for_year(Time.zone.now.year)
    unless available_cve_id
      raise StandardError, "No CVE ID available to assign"
    end

    cve_review.update!(
      decision: :assigned,
      assigned_cve_id: available_cve_id,
    )
    cve_review.cve.update!(assigner: current_user)
    if AdvisoryDB.cve_automatic_reservation_enabled?
      ReserveCVEJob.perform_later
    end
  end

  def cve_request_params
    {
      ghsa_id: GHSAIDGenerator.generate_unique_ghsa_id,
      actor_id: current_user.id,
      actor_login: current_user.login,
      advisory_permalink: cve_review_params[:confirm_reference],
      advisory_state: "open",
      title: cve_review_params[:title],
      description: cve_review_params[:description],
    }
  end

  def cve_review
    @cve_review ||= CVEReview.find_by!(ghsa_id: params.require(:ghsa_id))
  end

  def cve_review_params
    return @cve_review_params if defined?(@cve_review_params)

    @cve_review_params = params
      .require(:cve_review)
      .permit(
        :confirm_reference,
        :cvss_vectorString,
        :description,
        :product,
        :review_notes,
        :title,
        :vendor_name,
        misc_references: [],
        problemtype_values: [],
        version_values: [],
      )
  end

  def cve_reviews_rejection
    return @cve_reviews_rejection if defined?(@cve_reviews_rejection)

    @cve_reviews_rejection = CVEReviews::Rejection.new(reason_template: rejection_params[:reason_template], reason: rejection_params[:reason], replaced_by: rejection_params[:replaced_by])
  end

  def ghsl_request_params
    params.require(:cve_review).require(:ghsl_request).permit(
      :ghsl_id,
      :ghsl_issue,
    )
  end

  def record_curation_decision
    cve_review.record_curation_decision(type: "cve_review", decision: params[:action], curator: current_user.login)
  end

  def render_show_unprocessable_entity(error)
    flash.now[:alert] = "CVE review #{cve_review.ghsa_id} could not be published! An error occurred: #{error.message}"
    render action: :show, status: :unprocessable_entity, locals: {
      cve_review: cve_review,
      cve_request: cve_review.current_cve_request,
    }
  end

  def rejection_params
    params.require(:rejection).permit(:reason_template, :reason, :replaced_by)
  end

  def checks_passed_for_cve_review?
    CheckSuiteRunner.run_checks(review: cve_review)
    CheckSuiteRunner.checks_passed?(review: cve_review)
  end
end
