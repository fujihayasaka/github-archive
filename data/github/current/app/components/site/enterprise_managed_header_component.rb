# typed: true
# frozen_string_literal: true

class Site::EnterpriseManagedHeaderComponent < ApplicationComponent
  memoize def business
    current_user.enterprise_managed_business
  end

  memoize def show_enterprise_managed_header?
    return false unless logged_in?
    return false unless current_user.is_enterprise_managed?
    business.present?
  end

  memoize def show_data_residency?
    show_enterprise_managed_header? &&
    GitHub.multi_tenant_enterprise? &&
    GitHub::Config::Proxima.current_region_label.present?
  end

  def render?
    show_enterprise_managed_header?
  end
end
