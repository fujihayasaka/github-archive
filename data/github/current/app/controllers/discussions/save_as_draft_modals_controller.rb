# typed: true
# frozen_string_literal: true

class Discussions::SaveAsDraftModalsController < Discussions::BaseController
  before_action :require_discussion
  before_action :login_required
  before_action :require_modifiable_discussion

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  def show
    render Discussions::SaveAsDraftModalComponent.new(discussion: discussion), layout: false
  end

  private

  def require_modifiable_discussion
    unless user_or_global_feature_enabled?(:scheduled_discussions) && discussion.modifiable_by?(current_user)
      render_404
    end
  end

  def discussion
    T.must_because(super) { "#require_discussion ensures non-nil" }
  end
end
