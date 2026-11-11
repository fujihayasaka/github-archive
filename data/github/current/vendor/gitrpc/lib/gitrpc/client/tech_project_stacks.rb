# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    def tech_project_stacks(commit_oid, forced_rescan = false)
      ensure_valid_full_oid(commit_oid)
      send_message(:tech_project_stacks, commit_oid, forced_rescan)
    end
  end
end
