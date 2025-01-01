# typed: true
# frozen_string_literal: true

class Memexes::Items::SuggestedAssigneesController < Memexes::Controller
  include Memexes::MemexProjectItemDependency

  before_action :login_required
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :user_has_write_access
  before_action :require_verified_email
  before_action :require_actor_can_read_issue_suggestions, unless: :any_draft_issues?
  before_action :require_actor_can_add_assignees
  before_action :set_client_uid
  before_action :set_cache_control_no_store

  depends_on_clusters ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories, only: [:index]

  depends_on_clusters ApplicationRecord::Configurations,
    ApplicationRecord::Permissions, only: [:index], optional: true

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Spokes, only: [:index], optional: true

  def index
    assignees_target = this_item.draft_issue? ? this_item.content : item_content
    sorted_assignees = get_suggestions("assignees", assignees_target)
    render(json: { suggestions: sorted_assignees })
  end
end
