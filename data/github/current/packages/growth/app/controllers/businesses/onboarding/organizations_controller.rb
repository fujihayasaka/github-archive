# typed: strict
# frozen_string_literal: true

class Businesses::Onboarding::OrganizationsController < Businesses::BusinessController
  include AvatarHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    optional: true

  before_action :dotcom_required
  before_action :login_required
  before_action :unsuspended_business_required

  sig { returns(String) }
  def self.react_bundle_name
    "enterprise-onboarding"
  end

  sig { void }
  def new
    return render_404 unless current_user && Authz.domain.check_allowed(current_user, :create_enterprise_organizations, this_business)

    render_react_app(
      payload: { **business },
      title: "Create an organization for your enterprise",
      page_data: { hide_subnav: true }
    )
  end

  private

  sig { returns({ business: { name: String, slug: String, avatar_url: String } }) }
  def business
    this_business.as_json(only: %i[name slug]).deep_symbolize_keys
      .tap do |payload|
        payload[:business][:avatar_url] = avatar_url_for(this_business, 48 * 2)
      end
  end

  sig { void }
  def unsuspended_business_required
    return if GitHub.enterprise?
    return if current_user&.site_admin?
    return unless params[:slug] && this_business&.suspended?
    render_404
  end

  sig { returns(T.any(Business, Symbol)) }
  def resource_for_conditional_access
    this_business || :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
