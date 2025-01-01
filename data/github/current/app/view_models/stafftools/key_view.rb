# typed: true
# frozen_string_literal: true

module Stafftools
  class KeyView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :key

    def verifier_user_link
      if key.verifier
        login = key.verifier.bot? ? key.verifier.display_login : key.verifier.login
        helpers.link_to(login, urls.gh_stafftools_user_path(key.verifier))
      elsif key.verifier_id
        helpers.link_to("a deleted user",
          urls.stafftools_audit_log_path(query: audit_log_query))
      else
        "an unknown user"
      end
    end

    private

    def audit_log_query
      if GitHub.driftwood_ade_queries_enabled?
        "webevents | where user_id == #{key.verifier_id}"
      else
        "user_id:#{key.verifier_id}"
      end
    end
  end
end
