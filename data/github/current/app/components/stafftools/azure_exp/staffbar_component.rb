# typed: true
# frozen_string_literal: true

class Stafftools::AzureExp::StaffbarComponent < ApplicationComponent
  def render?
    user_feature_enabled?(:azure_exp_staffbar) || Rails.env.development?
  end
end
