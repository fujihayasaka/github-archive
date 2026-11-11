# typed: true
# frozen_string_literal: true

class Discussions::RepositoryTransfersController < Discussions::BaseController
  before_action :login_required
  before_action :require_discussion
  before_action :require_ability_to_transfer_discussion

  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "discussions/repository_transfers/show", locals: {
      discussion: discussion,
    }
  end

  def update
    new_repository = Repository.filter_spam_and_disabled_for(current_user).
      find_by(id: params[:repository_id])

    if new_repository.blank?
      discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
      flash[:error] = "You must select a repository to transfer this discussion to."
      return redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end

    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    transferrer = DiscussionRepositoryTransferrer.for_new_transfer(discussion,
      new_repository: new_repository, actor: current_user)

    if transferrer.start_transfer
      TransferDiscussionJob.perform_later(transferrer.discussion_transfer)

      flash[:notice] = "Discussion transfer to #{new_repository.name_with_display_owner} is in progress."
      redirect_to discussion_path(transferrer.new_discussion, new_repository)
    else
      flash[:error] = transferrer.error
      redirect_to agnostic_discussion_path(discussion, org_param: org_param)
    end
  end

  private

  def require_ability_to_transfer_discussion
    render_404 unless discussion&.transferrable_by?(current_user)
  end
end
