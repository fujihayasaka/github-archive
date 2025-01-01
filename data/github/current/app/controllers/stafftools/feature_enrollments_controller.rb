# typed: true
# frozen_string_literal: true

class Stafftools::FeatureEnrollmentsController < StafftoolsController

  before_action :require_feature_preview
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    view = create_view_model(Stafftools::User::FeatureEnrollmentsView, user: this_user)
    render "stafftools/feature_enrollments/show", layout: "layouts/stafftools/user/overview", locals: { view: view }
  end

  def toggle # rubocop:todo GitHub/UseRestfulActions
    if should_unenroll = this_user.feature_preview_enabled?(feature)
      this_user.disable_feature_preview(feature)
    else
      this_user.enable_feature_preview(feature)
    end

    flash[:notice] = "#{this_user.login} is now #{should_unenroll ? "unenrolled from" : "enrolled in"} #{feature}."

    redirect_to :back
  end

  private

  def require_feature_preview
    render_404 unless feature_preview_enabled?
  end

  def feature
    params[:feature]
  end
end
