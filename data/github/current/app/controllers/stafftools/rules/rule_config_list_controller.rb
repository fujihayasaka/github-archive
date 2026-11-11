# typed: strict
# frozen_string_literal: true

class Stafftools::Rules::RuleConfigListController < StafftoolsController
  include Repos::Rules::Concerns::RuleConfigList

  before_action do
    T.bind(self, Stafftools::Rules::RuleConfigListController)
    ensure_plan_supports_rules(repository: current_repository)
  end
  before_action :ensure_ref
  before_action :ensure_branch

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Ballast, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  sig { void }
  def index
    branch = params[:ref].delete_prefix("refs/heads/")

    render json: rule_schemas_by_branch(source: current_repository, user: current_user, branch:)
  end
end
