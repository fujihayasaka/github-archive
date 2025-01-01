# typed: true
# frozen_string_literal: true

require "github/config/business_user_account_activity"
require "audit/user_dormancy_actions"

if GitHub::Config::BusinessUserAccountActivity.business_user_account_activity_enabled?
  Audit::UserDormancyActions::USER_DORMANCY_ACTION_NAMES.each do |action|
    GitHub.subscribe(action) do |_name, _start, _ending, _transaction_id, payload|
      BusinessUserAccount::Activity.record_user_activity(payload)
    end
  end
end
