# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    def revert_range(commit_oid1, commit_oid2 = nil, info = {})
      send_message(:revert_range, commit_oid1, commit_oid2, info)
    end
  end
end
