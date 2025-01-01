# typed: true
# frozen_string_literal: true

class RepositoryUserListsController < AbstractRepositoryController
  include ActionView::Helpers::NumberHelper

  before_action :login_required
  before_action :render_sso_if_necessary, only: :show
  skip_before_action :ask_the_gatekeeper, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    only: [:show]

  def show
    lists_applied_set = UserList.applied_to(user_id: current_user.id, repository_ids: [current_repository.id])

    render(UserLists::MenuContentComponent.new(
      repository: current_repository,
      lists_applied_set: lists_applied_set,
    ), layout: false)
  end

  def update
    result = UserLists::ReplaceItemUserLists.call(
      user: current_user,
      item: current_repository,
      requested_list_ids: params.fetch(:list_ids, []),
      requested_list_names: params.fetch(:list_names, []),
      context: params[:context],
    )

    if result.success?
      respond_to do |wants|
        wants.json do
          render json: {
            didStar: result.did_star?,
            didCreate: result.did_create?,
            starCount: number_with_delimiter(current_repository.stargazer_count),
          }
        end
      end
    else
      head :unprocessable_entity
    end
  end

  private

  def require_active_external_identity_session?
    # opted out to be handled manually in show action to render a custom SAML SSO interstitial; see
    # #render_sso_if_necessary
    return false if action_name == "show"

    # opted out to let users add a public repo owned by an SSO org to their lists; keep this check
    # in sync with #render_sso_if_necessary so we don't show the SSO prompt for the same repos that
    # #update allows adding to lists
    return false if action_name == "update" && !current_repository.private?

    super
  end

  def render_sso_if_necessary
    unless !current_repository.private? || required_external_identity_session_present?
      render "repository_user_lists/sso", locals: { target: current_repository.owner }, layout: false
    end
  end

  def ip_allowlist_enforce(target)
    return head :forbidden unless request.xhr?
    render "repository_user_lists/ip_allowlist", locals: { target: target }, layout: false
    set_html_safe
  end
end
