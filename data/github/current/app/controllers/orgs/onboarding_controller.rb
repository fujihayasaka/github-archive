# typed: true
# frozen_string_literal: true

# This controller lists onboarding tasks for a organization on GitHub Enterprise Cloud trial.
class Orgs::OnboardingController < Orgs::Controller
  before_action :login_required
  before_action :organization_read_required
  before_action :non_emu_required
  before_action :dotcom_required

  extend T::Sig

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,

    # Required for render_404
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:tasks]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:tasks], optional: true

  def tasks # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?
    # It is an XHR request used by Onboarding::Organizations::OnboardingComponent.
    render partial: "orgs/onboarding_tasks/tasks", locals: {
      demo_repo: OrganizationOnboard::DemoRepository.repository_for(this_organization),
    }
  end

  def reset_onboarding_notice # rubocop:todo GitHub/UseRestfulActions
    current_user.reset_organization_notice(User::NoticesDependency::ORGANIZATION_NOTICES[:enterprise_trial_onboarding], this_organization, for_whole_org: true)

    redirect_to user_path(this_organization)
  end
end
