# typed: true
# frozen_string_literal: true

class Hovercards::CommitsController < AbstractRepositoryController
  # Opted out SAML to be handled manually in show action to render a custom SAML SSO interstitial
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr, only: :show

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    return render_404 unless current_commit

    return render_sso unless !current_repository.private? || required_external_identity_session_present?

    render "hovercards/commits/show", locals: { commit: current_commit }, layout: false
  end

  private

  # used to render in the conditional access enforcement pop-up
  def target_type
    "commit"
  end

  def render_sso
    render "hovercards/commits/sso", locals: { repository: current_repository, return_to_path: return_to_path }, layout: false
  end

  # only allow relative paths for the return_to option on the SSO link, otherwise link to the
  # user dashboard
  #
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
end
