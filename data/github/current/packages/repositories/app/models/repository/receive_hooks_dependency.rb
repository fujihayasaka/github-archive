# typed: true
# frozen_string_literal: true

module Repository::ReceiveHooksDependency
  extend T::Helpers

  requires_ancestor { Repository }

  def pre_receive_hooks
    @pre_receive_hooks ||= begin
      hooks = {}
      targets = PreReceiveHookTarget.for_hookable_and_parents(self)
                                    .includes(hook: [:environment])
                                    .order(Arel.sql("CASE hookable_type
                                                     WHEN 'Business'   THEN 0
                                                     WHEN 'User'       THEN 1
                                                     WHEN 'Repository' THEN 2
                                                     END"),
                                           :id)
      targets.each do |target|
        hook_id = target.hook_id
        current = hooks[hook_id]
        next if current && current.final?
        # delete existing entry so new one is inserted at the right order
        hooks.delete(hook_id)
        hooks[hook_id] = GitHub::PreReceiveHookEntry.new(
          target.hook.environment.id,
          target.hook.environment.checksum,
          hook_id,
          target.hook.repository_id,
          target.hook.script,
          target.enforcement_before_type_cast, # expecting the raw value, e.g. 2
          target.final,
        )
      end

      hooks.values.select { |entry| entry.enforcement != GitHub::PreReceiveHookEntry::DISABLED }
    end
  end

  def has_pre_receive_hooks?
    GitHub.pre_receive_hooks_enabled? && pre_receive_hooks.any?
  end

  # Control vars necessary for dispatching to the right hook over RPC
  def pre_receive_control_vars
    {
      githooks_env: GitHub.githooks_env,
      pre_receive_fallback_enabled: GitHub.pre_receive_fallback_enabled?,
    }
  end

  # Public: Returns the internal URL to notify of a git push.
  #
  # wiki - Should be true if you want to get the URL for the associated wiki.
  def post_receive_hook_url(wiki = false)
    if wiki
      "#{GitHub.githooks_api_url}/internal/repositories/#{name_with_owner}/wiki/git/pushes"
    else
      "#{GitHub.githooks_api_url}/internal/repositories/#{name_with_owner}/git/pushes"
    end
  end
end
