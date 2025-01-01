# typed: true
# frozen_string_literal: true

class Businesses::HooksController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_full_plan_required

  include HooksControllerMethods # All Hook related actions

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
    only: [:new]

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
    only: [:show]

  # include admin bundles for pre-receive hooks code
  if GitHub.single_business_environment?
    stylesheet_bundle :admin
    javascript_bundle :admin
  end

  stylesheet_bundle :settings

  private

  # Business hooks
  def current_context
    this_business
  end

  def default_events
    return %w(*) if GitHub.single_business_environment?
    super
  end

  def pre_receive_targets_with_hook # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @pre_receive_targets_with_hook ||= \
      PreReceiveHookTarget.where(hookable: GitHub.global_business)
        .includes(:hook).all.sorted_by("hook.name")
  end
  helper_method :pre_receive_targets_with_hook

end
