# typed: true
# frozen_string_literal: true

class MunichPlan
  ACTIONS_CHANGE_DATETIME = GitHub::Billing.timezone.parse("2020-05-14")
  ACTIONS_CHANGE_DATE = ACTIONS_CHANGE_DATETIME.to_date
  RELEASE_DATE = GitHub::Billing.timezone.parse("2020-04-14").to_date
end
