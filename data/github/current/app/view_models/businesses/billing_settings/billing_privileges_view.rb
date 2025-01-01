# typed: true
# frozen_string_literal: true

class Businesses::BillingSettings::BillingPrivilegesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business

  delegate :slug, to: :business

  def initialize(**args)
    super(args)

    @business = args[:business]
  end

  def menu_button_text
    members_can_make_purchases? ? "Enabled" : "Disabled"
  end

  def members_can_make_purchases?
    business.members_can_make_purchases?
  end
end
