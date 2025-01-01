# typed: true
# frozen_string_literal: true

class UnverifiedEmailController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  layout "application"

  javascript_bundle :marketing
  stylesheet_bundle :site

  def index
    return render_404 unless logged_in?
    return redirect_to(home_path) unless current_user.should_verify_email?

    # Don't show the flash notice that says
    # the exact same thing as this page.
    @hide_email_verification_warning = true

    # If we have bouncing emails, show details about that too
    if current_user.emails.user_entered_emails.all_bouncing.present?
      respond_to do |format|
        format.html do
          render "account/bouncing_email"
        end
      end
    else
      respond_to do |format|
        format.html do
          render "account/unverified_email"
        end
      end
    end
  end

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
