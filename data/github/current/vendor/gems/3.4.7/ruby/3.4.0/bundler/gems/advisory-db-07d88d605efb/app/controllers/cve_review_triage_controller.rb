# frozen_string_literal: true

class CVEReviewTriageController < InboxController
  before_action :record_curation_decision, only: [:open, :close]

  def index
    if next_cve_review.nil?
      redirect_to done_cve_review_triage_index_path
    else
      redirect_to cve_review_triage_path(next_cve_review)
    end

    reset_counts
  end

  def done
    render locals: {
      opened_count: opened_count,
      closed_count: closed_count,
      skipped_count: skipped_count,
      total_count: opened_count + closed_count + skipped_count,
    }
  end

  def show
    unless cve_review.curation_state_in_triage?
      flash[:alert] = "CVE review #{cve_review.ghsa_id} was already triaged. Moving on!"
      redirect_to_next_or_done
      return
    end

    render locals: {
      cve_review: cve_review,
      cve_request: cve_review.current_cve_request,
      related_cve_counts: related_cve_counts,
      opened_count: opened_count,
      closed_count: closed_count,
      skipped_count: skipped_count,
      total_count: opened_count + closed_count + skipped_count + remaining_count + 1,
      comment_templates: AdvisoryDB.comment_templates,
    }
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def open
    if cve_review.assigned?
      # Do nothing. The CVE review is already assigned.
    elsif cve_review.open?
      available_cve_id =
        if AdvisoryDB.cve_automatic_assignment_enabled?
          CVE.first_available_cve_id_for_year(Time.zone.now.year)
        else
          params[:assigned_cve_id]
        end
      if available_cve_id
        cve_review.decision = :assigned
        cve_review.assigned_cve_id = available_cve_id
        cve_review.comment = params[:comment].present? ? params[:comment].gsub(/\${{CVEID}}/, available_cve_id) : nil
        cve_review.notify!
        increment(:opened)

        if AdvisoryDB.cve_automatic_assignment_enabled?
          cve_review.cve.update!(assigner: current_user)
          if AdvisoryDB.cve_automatic_reservation_enabled?
            ReserveCVEJob.perform_later
          end
        end
      else
        flash[:alert] = "No CVE ID available for assignment."
      end
    else
      flash[:alert] = "CVE review #{cve_review.ghsa_id} could not be opened. Moving on!"
    end

    redirect_to_next_or_done
  end

  def close
    if cve_review.not_assigned?
      # Do nothing. The CVE review is already not assigned.
    elsif cve_review.open?
      cve_review.decision = :not_assigned
      cve_review.comment = params[:comment].presence
      cve_review.notify!
      increment(:closed)
    else
      flash[:alert] = "CVE review #{cve_review.ghsa_id} could not be closed. Moving on!"
    end

    redirect_to_next_or_done
  end

  def skip
    increment(:skipped)
    redirect_to_next_or_done
  end

  private

  def cve_review
    @cve_review ||= CVEReview.find_by!(ghsa_id: params.require(:ghsa_id))
  end

  def next_cve_review
    return @next_cve_review if defined? @next_cve_review

    @next_cve_review = remaining.first
  end

  def related_cve_counts
    related_cves = cve_review.related_cve_reviews
    {
      assigned: related_cves.assigned.count,
      closed: related_cves.curation_state_closed.count,
    }
  end

  def remaining_count
    @remaining_count ||= remaining.count
  end

  def remaining
    current_id = params[:ghsa_id] ? cve_review.id : 0
    CVEReview.curation_state_in_triage(after_id: current_id)
  end

  def opened_count
    session[:cve_review_triage_opened_count] || 0
  end

  def closed_count
    session[:cve_review_triage_closed_count] || 0
  end

  def skipped_count
    session[:cve_review_triage_skipped_count] || 0
  end

  def increment(state)
    raise ArgumentError unless state.in?(%i[opened closed skipped])

    key = :"cve_review_triage_#{state}_count"
    session[key] ||= 0
    session[key] += 1
  end

  def reset_counts
    session.delete(:cve_review_triage_opened_count)
    session.delete(:cve_review_triage_closed_count)
    session.delete(:cve_review_triage_skipped_count)
  end

  def redirect_to_next_or_done
    if next_cve_review
      redirect_to cve_review_triage_path(next_cve_review)
    else
      redirect_to done_cve_review_triage_index_path
    end
  end

  def record_curation_decision
    cve_review.record_curation_decision(type: "cve_triage", decision: params[:action], curator: current_user.login)
  end
end
