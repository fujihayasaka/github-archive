# typed: true
# frozen_string_literal: true

class Profiles::ContributionsController < ApplicationController
  include ProfilesHelper
  include UserContributionsHelper
  include Profiles::ContributionGraphDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: [:show]

  before_action :require_xhr
  before_action :require_flag_enabled
  before_action :require_user_is_user
  before_action :require_profile_visible

  rate_limit_requests \
    only: :show,
    ttl: :profiles_rate_limit_ttl,
    max: :profiles_rate_limit_max,
    key: :profiles_rate_limit_key

  def show
    if show_mobile_year_picker? || activity_overview_enabled?
      render partial: "users/tabs/contributions_new", locals: {
        collector: timeline_collector,
      }
    else
      render partial: "users/tabs/contributions", locals: {
        collector: timeline_collector,
      }
    end
  end

  private

  memoize def show_mobile_year_picker?
    current_user&.feature_flag_enabled?(:mobile_year_picker, default: false)
  end

  def require_flag_enabled
    return if async_contributions_enabled?
    render_404
  end

  def require_user_is_user
    return if this_user&.user?
    render_404
  end

  def require_profile_visible
    return if private_profile_override?
    return unless this_user.private_profile_for?(current_user)
    render_404
  end

  # NOTE: this_user is required by `require_user_is_user` action filter so CAP is not skipped
  def target_for_conditional_access
    return this_user if this_user.present?
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
