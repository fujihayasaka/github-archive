# typed: true
# frozen_string_literal: true

class Marketplace::ActionsVersionsController < ApplicationController

  VERSIONS_PER_PAGE = 5

  before_action :marketplace_required

  before_action :this_action_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    latest_release = this_action.published_releases.order(created_at: :desc, id: :desc).first

    releases = this_action.published_releases.order(created_at: :desc, id: :desc).paginate(page: params[:page], per_page: VERSIONS_PER_PAGE)

    render partial: "marketplace/actions/version_item/show", locals: {
      releases: releases,
      repository_action: this_action,
      latest_tag: latest_release,
      limit: VERSIONS_PER_PAGE
    }, layout: false
  end

  private

  memoize def this_action
    RepositoryAction.listed.find_by(slug: params[:slug])
  end

  def require_active_external_identity_session?
    false
  end

  def this_action_required
    render_404 unless this_action.present?
  end

  # Bypassing CAP is fine here as this_action is required.
  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_action # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_action.owner
  end
end
