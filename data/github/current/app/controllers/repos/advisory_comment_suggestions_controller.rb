# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

class Repos::AdvisoryCommentSuggestionsController < AbstractRepositoryController
  include OcticonsHelper
  include TextHelper

  before_action :login_required
  before_action :check_feature_is_enabled
  before_action :authorize_advisory_comments
  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:issues]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    only: [:mentions]

  def mentions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: suggester.mentions
      end
    end
  end

  def issues # rubocop:todo GitHub/UseRestfulActions
    # issue-suggester.ts expects some specific properties be set on this response.
    # The cross reference feature was not working on the frontend because properties
    # such as type and icons were missing. To fix that, we define those properties
    # using the code copied from the SuggestionsController:
    #   https://github.com/github/github/blob/73ae9259370600485b02ead6e18434b25c84b109/app/controllers/suggestions_controller.rb#L30-L57
    # TODO: consider integrating our logic here into the flow inside
    # SuggestionsController so we no longer copy and paste.
    issues = suggester.issues.map do |elem| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      type = if elem.respond_to?(:pull_request_id?)
        if elem.pull_request_id?
          "pull_request"
        elsif elem.respond_to?(:closed_at?)
          elem.closed_at? ? "issue_closed" : "issue_open"
        end
      else
        "discussion"
      end

      title = (type == "discussion") ? html_escape(elem.title) : title_markdown(elem.title)
      { id: elem.id, number: elem.number, title: title, type: type }
    end

    icons = {
      pull_request: octicon("git-pull-request"),
      pull_request_closed: octicon("git-pull-request-closed"),
      pull_request_draft: octicon("git-pull-request-draft"),
      issue_open: octicon("issue-opened", class: "open"),
      issue_closed: octicon("issue-closed", class: "closed"),
      discussion: octicon("comment-discussion"),
    }

    respond_to do |format|
      format.json do
        render json: {
          icons: icons,
          suggestions: issues
        }
      end
    end
  end

  private

  def suggester
    Suggester::RepositoryAdvisorySuggester.new(
      viewer: current_user,
      repository: current_repository,
      advisory: current_advisory)
  end

  memoize def current_advisory
    current_repository.repository_advisories.find_by!(ghsa_id: params[:id])
  end

  def check_feature_is_enabled
    render_404 unless current_repository.advisories_enabled?
  end

  def authorize_advisory_comments
    render_404 unless current_advisory.writable_by?(current_user)
  end
end
