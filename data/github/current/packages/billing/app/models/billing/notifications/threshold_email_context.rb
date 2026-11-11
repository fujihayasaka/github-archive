# typed: strict
# frozen_string_literal: true

class Billing::Notifications::ThresholdEmailContext < T::Struct
  prop :progress_bar_details_text, String
  prop :progress_bar_title, String
  prop :threshold, Integer
  prop :text, String
  prop :usage_reset_date_text, String
  prop :mail_subject, String
  prop :mail_icon, String
  prop :mail_product_title, String
  prop :month, T.nilable(Integer)
  prop :year, T.nilable(Integer)
  prop :exclude_cost_center_usage, T::Boolean, default: false
  prop :recommendation_text, T.nilable(String), default: nil
  prop :disclaimer_text, T.nilable(String), default: nil
end
