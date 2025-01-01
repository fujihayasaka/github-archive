# frozen_string_literal: true

class AdvisoryReviewApprovalsController < InboxController
  def create
    user = User.find_by!(login: params[:curator])
    advisory_review.approvals.create!(user_id: user.id)

    redirect_to advisory_review,
      notice: "#{params[:curator]} was successfully assigned to advisory review #{advisory_review.ghsa_id}!"
  rescue StandardError => error
    flash.now[:alert] = "#{params[:curator]} could not be assigned! An error occurred."
    Failbot.report!(error)
    render "advisory_reviews/show", status: :unprocessable_entity, locals: {
      advisory_review: advisory_review,
    }
  end

  def update
    approval = AdvisoryReviewApproval.find(params.require(:id))
    previously_assigned_curator = approval.user.login
    new_curator = params[:curator]

    if new_curator.blank?
      approval.destroy!

      redirect_to advisory_review,
        notice: "#{previously_assigned_curator} was successfully unassigned from advisory review #{advisory_review.ghsa_id}!"
    else
      approval.update!(user_id: User.find_by!(login: new_curator).id)

      redirect_to advisory_review,
        notice: "#{new_curator} was successfully assigned to advisory review #{advisory_review.ghsa_id}!"
    end
  rescue StandardError => error
    flash.now[:alert] = "#{new_curator} could not be assigned to advisory review #{advisory_review.ghsa_id}! An error occurred."
    Failbot.report!(error)
    render "advisory_reviews/show", status: :unprocessable_entity, locals: {
      advisory_review: advisory_review,
    }
  end

  private

  def advisory_review
    return @advisory_review if defined? @advisory_review

    @advisory_review = AdvisoryReview.find_by!(ghsa_id: params.require(:ghsa_id))
  end
end
