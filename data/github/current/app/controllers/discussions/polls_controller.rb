# typed: true
# frozen_string_literal: true

class Discussions::PollsController < Discussions::BaseController
  before_action :login_required, only: :edit
  before_action :require_discussion
  before_action :require_poll

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit, :show], optional: true

  def show
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    render(
      Discussions::PollComponent.new(
        discussion_number: discussion.number,
        repository: current_repository,
        poll: poll,
        options: poll.options,
        preview: false,
        locked: discussion.locked?
      ),
      layout: false
    )
  end

  def edit
    return render_404 unless request.xhr?

    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    return render_404 unless discussion.modifiable_by?(current_user)

    render Discussions::PollFormComponent.new(
      discussion: discussion,
      category: discussion.category,
      hidden: false,
    ), layout: false
  end

  private

  memoize def poll
    discussion&.poll
  end

  def require_poll
    render_404 unless poll
  end
end
