# typed: true
# frozen_string_literal: true

require "audit/user_dormancy_actions"

Audit::UserDormancyActions::USER_DORMANCY_ACTION_NAMES.each do |action|
  GitHub.subscribe(action) do |_name, _start, _ending, _transaction_id, payload|
    BusinessUserAccount::Activity.record_user_activity(payload)
  end
end
