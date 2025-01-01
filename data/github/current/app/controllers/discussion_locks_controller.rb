# typed: true
# frozen_string_literal: true

class DiscussionLocksController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  before_action :require_repository_not_migrating
  before_action :require_ability_to_lock_discussion, only: [:create]
  before_action :require_ability_to_unlock_discussion, only: [:destroy]
  before_action :add_spamurai_form_signals

  def create
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    unless discussion.locked?
      allow_reactions = params[:allow_reactions] == "on"
      GitHub.dogstats.increment("lock_discussion", tags: ["allow_reactions:#{allow_reactions}"])
      discussion.lock(actor: current_user, allow_reactions: allow_reactions)
    end
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  def destroy
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    if discussion.locked?
      discussion.unlock(actor: current_user)
    end
    redirect_to agnostic_discussion_path(discussion, org_param: org_param)
  end

  private

  def require_repository_not_migrating
    if current_repository&.locked_on_migration?
      discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
      flash[:error] = "You can't perform that action at this time, the repository has been " \
        "locked for migration."
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end
  end

  def require_ability_to_lock_discussion
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    unless discussion.lockable_by?(current_user)
      flash[:error] = "You can't perform that action at this time."
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end
  end

  def require_ability_to_unlock_discussion
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    unless discussion.unlockable_by?(current_user)
      flash[:error] = "You can't perform that action at this time."
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end
  end
end
