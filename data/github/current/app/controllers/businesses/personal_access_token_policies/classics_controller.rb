# typed: true
# frozen_string_literal: true

module Businesses::PersonalAccessTokenPolicies
  class ClassicsController < Businesses::BusinessController
    before_action :business_owner_required
    before_action :require_feature_flags
    before_action :business_full_plan_required

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Copilot,
      ApplicationRecord::Billing,
      only: [:index]

    def index
      render "businesses/personal_access_token_policies/classic"
    end

    private

    def require_feature_flags
      return render_404 unless current_user.patsv2_enabled?
      return if this_business.patsv2_enabled?

      redirect_to settings_personal_access_tokens_onboarding_enterprise_path(this_business)
    end
  end
end
