# typed: true
# frozen_string_literal: true

class Businesses::GettingStarted::TaskComponent < ApplicationComponent
  sig { returns(Business) }
  attr_reader :business

  sig { returns(Hash) }
  attr_reader :task

  def initialize(business:, task:)
    @business = business
    @task = task
  end

  private

  sig { returns(T::Boolean) }
  def render?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless business.present?
    return false unless current_user.present?
    return false unless business.owner?(current_user)
    return false unless task.present?
    return false unless task_valid?
    return false unless business.trial?
    true
  end

  def task_valid?
    return false unless task[:title].is_a?(String) && task[:title].present?
    return false unless task[:description].is_a?(String) && task[:description].present?
    return false unless task[:icon].is_a?(Symbol) || task[:icon].is_a?(String)
    return false unless task[:id].is_a?(String) && task[:id].present?
    return false unless task[:icon_color].nil? || task[:icon_color].is_a?(String)
    return false unless task[:text_color_class] || task[:text_color_class].is_a?(String)
    true
  end
end
