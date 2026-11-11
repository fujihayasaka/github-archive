# typed: true
# frozen_string_literal: true

class TrackingBlockMenuController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam

  before_action :login_required

  include HierarchyHelper
  include ControllerMethods::Issues

  def show
    issue_id = params[:id]
    uuid = params[:uuid]
    type = params[:type]

    child_issue = Issue.find_by(id: issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    render_404 and return unless child_issue

    parsed_url = GitHub::IssueReferenceParser.parse_reference(request.referrer)

    # instrument the click for hydro events. We need the child item's parent issue info to get meaningful data
    # from the click. To get that we use the referrer header to parse the parent url to get the nwo and issue number.
    unless parsed_url.nil?
      nwo, number = parsed_url.values_at(:nwo, :number)
      owner_login, name = nwo.split("/")

      parent_repository = Repository.find_by(name: name, owner_login: owner_login)
      parent_issue = parent_repository&.issues&.find_by(number: number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      # Add info for parent issue, repo, user, etc.
      instrument_tasklist_block_item_metadata_menu_click(
        actor: current_user,
        parent_repository: parent_repository,
        parent_issue: parent_issue,
        child_issue: child_issue,
        menu_type: type
      )
    end

    render "tracking_block/tasklist_menu", layout: false, locals: { issue: child_issue, uuid: uuid, type: type, can_update: child_issue&.viewer_can_update?(current_user) }
  end
end
