# typed: true
# frozen_string_literal: true

class Memexes::Items::SuggestedLabelsController < Memexes::Controller
  include Memexes::MemexProjectItemDependency

  before_action :login_required
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_write_access
  before_action :require_verified_email
  before_action :require_non_draft_issue_these_items
  before_action :require_actor_can_read_issue_suggestions, unless: :any_draft_issues?
  before_action :require_these_items_labelable
  before_action :set_client_uid
  before_action :set_cache_control_no_store

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes, only: [:index], optional: true

  def index
    suggestions = get_suggestions("labels", item_content)
    render(json: { suggestions: suggestions })
  end
end
