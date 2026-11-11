# typed: strict
# frozen_string_literal: true

class JobStatus
  class DataStore < ApplicationRecord::Domain::UsersBallast
    self.table_name = "job_status_subscription_key_values"
  end
end
