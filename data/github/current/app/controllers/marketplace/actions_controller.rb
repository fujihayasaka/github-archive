# typed: true
# frozen_string_literal: true

class Marketplace::ActionsController < ApplicationController

  include GitHub::Memoizer
  include OcticonsHelper
  include ReactHelper

  before_action :marketplace_required

  before_action :login_required, only: :destroy
  before_action :this_action_required
  before_action :this_action_admin_required, only: :destroy

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  CONTRIBUTOR_LIMIT = 12

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def self.react_bundle_name
    "marketplace-react"
  end

  def show
    context_region_preset :marketplace

    if user_feature_enabled?(:marketplace_actions_react)
      render_react_app(
        payload: Marketplace::Payloads::ShowAction.new(repository_action: this_action).call,
        title: "Marketplace",
        ssr: true,
      )
    else
      repository = this_action.repository

      if GitHub.flipper[:action_package_marketplace].enabled?(current_user) && this_action.action_package_listed?
        redirect_to packages_two_view_path(user_type: this_action.owner.organization? ? "orgs" : "users", ecosystem: "container", name: repository, user_id: this_action.owner) and return
      end

      selected_version = params[:version] || ""

      releases = this_action.published_releases.order(pending_tag: :desc, id: :desc).limit(10)
      latest_release = Releases::Public.latest_for_repository(repository, current_user) || releases.latest.first

      return render_404 unless latest_release

      if selected_version.present?
        selected_release = this_action.releases.find_by_tag_name(selected_version)
        if selected_release.nil?
          flash[:error] = "Sorry, we couldn’t find that version of this Action. Here’s the latest version."
          redirect_to marketplace_action_path(params[:slug]) and return
        end
      end

      top_contributors = repository.top_contributors(
        limit: CONTRIBUTOR_LIMIT,
        viewer: current_user,
        skip_private_profiles: true,
      )

      if GitHub.flipper[:marketplace_new_layout].enabled?(current_user)
        contributor_count = CommitContribution.contributors_count_for_repository(repository)

        render "marketplace/actions/v2/show", locals: {
          repository_action: this_action,
          selected_release: selected_release,
          latest_release: latest_release,
          releases: releases,
          repository: repository,
          selected_version: selected_version,
          readme_html: this_action_readme_html(repository, selected_version),
          top_contributors: top_contributors,
          contributor_count: contributor_count
        }
      else
        render "marketplace/actions/show", locals: {
          repository_action: this_action,
          selected_release: selected_release,
          latest_release: latest_release,
          releases: releases,
          repository: repository,
          selected_version: selected_version,
          readme_html: this_action_readme_html(repository, selected_version),
          top_contributors: top_contributors
        }
      end
    end
  end

  def destroy
    this_action.delisted!

    redirect_to marketplace_path, notice: "Okay, #{this_action.name} has been delisted."
  end

  private

  def ip_allowlist_enforceable
    return :no unless action_name == "destroy"
    :yes
  end

  def require_active_external_identity_session?
    return false unless action_name == "destroy"
    true
  end

  def two_factor_enforceable
    return :no unless action_name == "destroy"
    :yes
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_action # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_action.owner
  end

  memoize def this_action
    RepositoryAction.listed.find_by(slug: params[:slug]) if GitHub::UTF8.valid_unicode3?(params[:slug])
  end

  def this_action_required
    render_404 unless this_action.present?
  end

  def this_action_admin_required
    render_404 unless this_action.adminable_by?(current_user) || T.must(current_user).can_admin_repository_actions?
  end

  def this_action_readme_html(repository, selected_version)
    committish = selected_version.presence || repository.default_branch
    readme = this_action.readme(committish: committish)
    return unless readme
    context = {
      entity: repository,
      blob: readme,
      name: readme.path,
      anchor_icon: octicon("link"), # rubocop:disable Primer/PrimerOcticon
      path: File.dirname(readme.path),
      committish: committish,
    }

    GitHub::Goomba::MarkupPipeline.to_html(nil, context, cache_settings: { use_cache: true })
  end
end
