# typed: true
# frozen_string_literal: true

class Hovercards::DiscussionsController < AbstractRepositoryController
  # Opted out SAML to be handled manually in show action to render a custom SAML SSO interstitial
  include Hovercards::ConditionalAccessMethods

  before_action :require_feature
  before_action :require_xhr
  before_action :require_discussion

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:show],
    optional: true

  def show
    return render_sso unless !current_repository.private? || required_external_identity_session_present?

    comment = if params[:comment_id]
      discussion.comments.find_by_id(params[:comment_id].to_i)
    elsif discussion.chosen_comment
      discussion.chosen_comment
    else
      discussion.latest_comment_for(current_user)
    end

    hydro_data = params.slice(:event_type, :hover_target, :user_id, :repository, :number, :query, :payload).to_unsafe_h

    render "hovercards/discussions/show", locals: {
      discussion: discussion,
      comment: comment,
      hydro_data: hydro_data,
    }, layout: false
  end

  private

  # used to render in the conditional access enforcement pop-up
  def target_type
    "discussion"
  end

  # only allow relative paths for the return_to option on the SSO link, otherwise link to the
  # user dashboard
  def return_to_path
    return home_path unless params[:current_path]
    parsed = Addressable::URI.parse(params[:current_path])

    if parsed.relative? && parsed.host.nil?
      parsed.userinfo = nil
      parsed.normalize.to_s
    else
      home_path
    end
  end

  def target_for_conditional_access
    current_repository.organization || current_repository.owner
  end

  # overriding resource for conditional access from app/controllers/repository_controller_methods.rb
  def resource_for_conditional_access
    # defaulting to `target_for_conditional_access`
    self
  end

  def render_sso
    render "hovercards/discussions/sso", layout: false
  end

  def require_feature
    render_404 unless current_repository&.discussions_active?
  end

  memoize def discussion
    Discussion.filter_spam_for(current_user).
      for_repository(current_repository).
      with_number(params[:number].to_i).first
  end

  def require_discussion
    render_404 unless discussion && discussion.readable_by?(current_user)
  end
end
