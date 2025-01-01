# typed: true
# frozen_string_literal: true

class Billing::Settings::Education::OverviewComponentPreview < ViewComponent::Preview
  def with_monalisa
    render Billing::Settings::Education::OverviewComponent.new(user: monalisa || new_user)
  end

  def with_new_user
    render Billing::Settings::Education::OverviewComponent.new(user: new_user)
  end

  private

  def monalisa
    User.find_by(login: "monalisa")
  end

  def new_user
    User.new(login: "BillingSettingsEdDevPackUser")
  end
end
