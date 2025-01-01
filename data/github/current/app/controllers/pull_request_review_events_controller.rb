# typed: true
# frozen_string_literal: true

class PullRequestReviewEventsController < AbstractRepositoryController
  include PullRequests::DatabaseSelection

  before_action :login_required
  before_action :load_current_pull_request

  prepend_around_action :use_repository_cluster_replicas, only: [:create]

  def create
    if params[:cancel] == "1"
      # Cancel pending comments
      # TODO: Handle failure case
      current_review = @pull.latest_pending_review_for(current_user)
      return head 404 unless current_review

      current_review.destroy_pending_comments
      flash[:notice] = "Your pending review comments have been discarded."

      redirect_to pull_request_path(@pull)
    else
      attrs = params[:pull_request_review] || {}
      event = attrs["event"]

      # This is a guard in case a user enables the "accept/reject" form in the inspector
      event = "comment" unless @pull.allows_non_comment_reviews_from?(reviewer: current_user)

      head_sha = params[:head_sha]

      current_review = @pull.latest_pending_review_for(current_user) ||
                       @pull.reviews.new(user_id: current_user.id, head_sha: head_sha)
      current_review.body = attrs[:body] unless current_review.body.nil? && attrs[:body].blank?

      if head_sha
        current_review.head_sha = head_sha
        current_review.merge_base_sha = @pull.find_best_merge_base_sha(head_sha: head_sha)
      end

      Rails.logger.debug { "[pull_request_reviews#update] #{event}! for review" }
      event_success = case event
      when "approve"
        current_review.approve!
      when "reject", "request_changes"
        current_review.request_changes!
      when "comment"
        current_review.comment!
      else
        raise ArgumentError, "Invalid event"
      end

      Rails.logger.debug { "[pull_request_reviews#update] completed #{event}!; event_success #{event_success}" }

      if event_success
        if @pull.open?
          flash[:notice] = "Your review was submitted successfully."
        else
          flash[:warn] = "Your review was submitted on a #{@pull.state.to_sym} pull request."
        end

        if current_review.show_in_timeline?
          redirect_to current_review.permalink(include_host: false)
        else
          redirect_to "#{pull_request_path(@pull)}"
        end
      else
        if current_review.halted?
          flash[:error] = current_review.halted_because
        else
          flash[:error] = "There was a problem submitting your review"
        end
        redirect_to "#{pull_request_path(@pull)}/files"
      end
    end
  end

  def quick_approve # rubocop:todo GitHub/UseRestfulActions
    # Recent review must be rejected in order to create a quick approval.
    current_review = @pull.latest_enforced_review_for(current_user)
    return head :not_acceptable if !current_review
    return head :not_acceptable if !current_review.changes_requested?

    merge_base_sha = @pull.find_best_merge_base_sha

    review = PullRequestReview.transaction do
      @pull.reviews.create(user: current_user, head_sha: @pull.head_sha, merge_base_sha: merge_base_sha).tap do |review|
        review.approve! if review.persisted?
      end
    end

    if !review.persisted? || review.halted?
      errors = review.errors.full_messages.tap do |errors|
        errors << review.halted_because if review.halted_because.present?
      end
      error_message = errors.to_sentence || "Whoops! Something went wrong. Please try again."
      flash[:error] = error_message
    else
      flash[:notice] = "Your review was submitted successfully."
    end

    redirect_to :back
  end

  def dismiss # rubocop:todo GitHub/UseRestfulActions
    current_review = @pull.reviews.find(params[:id])

    return head 404 unless current_review && current_review.can_be_dismissed_by?(current_user)
    return head :not_acceptable if current_review.dismissed?

    success = current_review.dismiss!(current_user, message: params[:message])

    if success && current_review.valid?
      flash[:notice] = "You successfully dismissed #{current_review.user.display_login}'s review."
    else
      if current_review.halted?
        flash[:error] = current_review.halted_because
      else
        flash[:error] = "Whoops! Something went wrong. Please try again."
      end
    end

    redirect_to :back
  end

  private

  def load_current_pull_request
    @pull = current_repository.issues.find_by_number(params[:pull_id].to_i).try(:pull_request)
    render_404 unless @pull
  end

  def route_supports_advisory_workspaces?
    true
  end

  def use_repository_cluster_replicas(&block)
    use_replica_clusters([ApplicationRecord::Repositories], &block)
  end
end
