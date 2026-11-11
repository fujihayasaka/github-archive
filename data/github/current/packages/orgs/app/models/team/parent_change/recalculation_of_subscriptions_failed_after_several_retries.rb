# typed: true
# frozen_string_literal: true

module Team::ParentChange
  class RecalculationOfSubscriptionsFailedAfterSeveralRetries < Team::ParentChange::Error
    attr_reader :org_id, :last_error, :retries

    def initialize(org_id, retries, last_error)
      super("#{retries} attempts to recalculate subscriptions after a team's parent changed inside Organization##{org_id} failed.")
      @org_id = org_id
      @retries = retries
      @last_error = last_error
    end
  end
end
