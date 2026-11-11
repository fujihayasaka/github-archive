# typed: true
# frozen_string_literal: true

class Memexes::PartialsController < Memexes::Controller
  preload_features [:org_feature_helper]

  before_action :login_required
  before_action :disable_color_modes
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :set_client_uid

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Iam,
    only: [:new]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  # We chose to name this action `new` because it will render a dialog box that will create a copy of a project. We had
  # to make the action name restful because of a rubocop rule that we have. As we expand this partial controller to be
  # more generic, we should revisit this and name it accordingly while also dismissing the rubocop rule.
  def new
    return render_404 unless this_memex.viewer_can_read?(current_user)

    copy_as_template = params[:copy_as_template] == "true"

    return render_404 if copy_as_template && !this_memex.owner.is_a?(Organization)

    if copy_as_template || this_memex.private?
      return render_404 unless this_memex.viewer_can_write?(current_user)
    end

    if params[:template_id]
      return render_404 if !this_memex.owner.is_a?(Organization)

      render(Memex::ProjectList::CopyProjectFromTemplateDialogComponent.new(project: this_memex, current_user: current_user, template_id: params[:template_id]), layout: false)
    else
      render(Memex::ProjectList::CopyProjectDialogComponent.new(project: this_memex, copy_as_template: copy_as_template), layout: false)
    end
  end
end
