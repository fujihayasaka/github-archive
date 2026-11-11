# typed: true
# frozen_string_literal: true

module Team::ParentChange
  class RecalculationFailedAfterSeveralRetries < Team::ParentChange::Error
    attr_reader :org_id, :last_error, :retries

    def initialize(org_id, retries, last_error)
      super("Failed after retrying #{retries} times to recalculate abilities after a team's parent changed inside Organization##{org_id}. Proceeding to repair the abilities for the org.")
      @org_id = org_id
      @retries = retries
      @last_error = last_error
    end
  end
end
