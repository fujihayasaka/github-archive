# typed: true
# frozen_string_literal: true

class Businesses::PreReceiveHookTargets::IndexPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

  def enforcement_class(target)
    target.enforcement
  end

  def repository_display(repo)
    repo.name_with_display_owner
  end

  def audit_log_query(target)
    "data.pre_receive_hook_id:#{target.hook.id} (action:pre_receive_hook.warned_push OR action:pre_receive_hook.rejected_push)"
  end

  def audit_log_kql_query(target)
    <<~KQL
      webevents
      | where data.pre_receive_hook_id == '#{target.hook.id}'
      | where (action == 'pre_receive_hook.warned_push' or action == 'pre_receive_hook.rejected_push')
    KQL
  end
end
