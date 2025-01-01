# typed: true
# frozen_string_literal: true

# This job is responsible for changing the state of custom rules whenever the GHAS enablement status on the
# repository changes. Rules should be considered inactive with the state being `ghas_disabled` when GHAS is disabled
# on a repository. When GHAS is enabled on a repository, rules should be considered `active`.
class RefreshRuleStateOnGhasEnablementChangeJob < ApplicationJob
  queue_as :vulnerability_identification

  retry_on_dirty_exit
  retry_on_recoverable_exceptions attempts: 10

  def perform(repository:, ghas_enabled:)
    if ghas_enabled
      VulnerabilityAlertRule.mark_ghas_disabled_rules_as_active(repository: repository)
    else
      VulnerabilityAlertRule.mark_active_rules_as_ghas_disabled(repository: repository)
    end
  end
end
