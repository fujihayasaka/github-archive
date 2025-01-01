# typed: true
# frozen_string_literal: true

module Business::GettingStartedDependency
  include BusinessesHelper
  include GitHub::Memoizer

  extend T::Helpers

  requires_ancestor { Business }

  SECRET_SCANNING_PAGE_VIEWED_KEY = "business.page_viewed.secret_scanning"
  CODE_SCANNING_PAGE_VIEWED_KEY = "business.page_viewed.code_scanning"

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def render_getting_started_widget?(viewer)
    return false unless getting_started_widget_can_be_rendered?
    return false unless viewer.present?
    return false unless owner?(viewer)
    return false if viewer == trial_first_emu_owner
    true
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_organization?
    return false if GitHub.single_business_environment?
    return false unless trial?
    return true if organizations.any?
    false
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_invited_owner?
    return false if GitHub.single_business_environment?
    return false unless trial?
    admins(role: Business::OWNER_ROLE).count + pending_admin_invitations(role: Business::OWNER_ROLE).count >= 2
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_invited_member?
    return false if GitHub.single_business_environment?
    return false unless trial?
    pending_unaffiliated_invitations.present? || business.user_accounts.exclusive_unaffiliated_role.present?
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_verified_identity_for_copilot?
    return false if GitHub.single_business_environment?
    return false unless trial?
    return false unless has_valid_payment_method?
    true
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_two_copilot_seats_assigned?
    return false if GitHub.single_business_environment?
    return false unless trial?

    Copilot::Seat.for_business(business).count >= 2
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_secret_scanning?
    return false if GitHub.single_business_environment?
    return false unless trial?
    return false unless secret_scanning_page_viewed?

    business.organizations.any? do |org|
      org.repositories.any? do |repo|
        if SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_enabled?(repo)
          return true
        end
      end
    end
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_code_scanning?
    return false if GitHub.single_business_environment?
    return false unless trial?
    return false unless code_scanning_page_viewed?

    business.organizations.any? do |org|
      org.repositories.any? do |repo|
        return true if CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository: repo)
      end
    end
    false
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_saml_sso?
    return false if GitHub.single_business_environment?
    return false unless trial?
    saml_sso_enabled?
  end

  sig { returns(T::Boolean) }
  memoize def trial_with_readme?
    return false if GitHub.single_business_environment?
    return false unless trial?
    business.long_description.present?
  end

  sig { returns(T::Boolean) }
  memoize def show_security_center_getting_started_info?
    return false if GitHub.single_business_environment?
    return false unless trial?
    return false unless dfd_trial?
    return false unless FeatureFlag.vexi.enabled?(:digital_front_door_getting_started, business, default: false)
    return true if organizations.empty?
    return false if Repository.where(owner_id: organization_ids).exists?
    true
  end

  sig { returns(T::Boolean) }
  memoize def trial_getting_started_pages_viewing_required?
    return false if GitHub.single_business_environment?
    return false unless trial?
    return false unless dfd_trial?
    FeatureFlag.vexi.enabled?(:digital_front_door_getting_started, business, default: false)
  end

  sig { void }
  def mark_secret_scanning_page_viewed
    ActiveRecord::Base.connected_to(role: :writing) do
      Growth::KV.store.set(SECRET_SCANNING_PAGE_VIEWED_KEY, "true", expires: page_viewed_kv_expires_at)
    end
  end

  sig { void }
  def mark_code_scanning_page_viewed
    ActiveRecord::Base.connected_to(role: :writing) do
      Growth::KV.store.set(CODE_SCANNING_PAGE_VIEWED_KEY, "true", expires: page_viewed_kv_expires_at)
    end
  end

  sig { returns(T::Boolean) }
  def secret_scanning_page_viewed?
    ActiveRecord::Base.connected_to(role: :reading) do
      Growth::KV.store.get(SECRET_SCANNING_PAGE_VIEWED_KEY).value { nil } == "true"
    end
  end

  sig { returns(T::Boolean) }
  def code_scanning_page_viewed?
    ActiveRecord::Base.connected_to(role: :reading) do
      Growth::KV.store.get(CODE_SCANNING_PAGE_VIEWED_KEY).value { nil } == "true"
    end
  end

  private

  sig { returns(Time) }
  def page_viewed_kv_expires_at
    trial_expires_at + 90.days
  end

  sig { returns(T::Boolean) }
  memoize def getting_started_widget_can_be_rendered?
    return false if GitHub.single_business_environment?
    return false unless business.trial?
    return false if business.trial_expired?
    feature_flag_enabled?(:digital_front_door_getting_started, default: false)
  end

  sig { returns(T.nilable(User)) }
  memoize def trial_first_emu_owner
    return nil unless business.enterprise_managed?
    business.find_first_emu_owner
  end
end
