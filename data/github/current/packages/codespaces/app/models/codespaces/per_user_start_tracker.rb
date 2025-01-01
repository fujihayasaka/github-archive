# typed: true
# frozen_string_literal: true

module Codespaces
  class PerUserStartTracker

    def initialize(user)
      @user = user
    end

    def track_start(codespace)
      ActiveRecord::Base.connected_to(role: :writing) { Codespaces::Kv.store.set(cache_key, codespace.guid, expires: 1.minute.from_now) }
    end

    def codespace_most_recently_started?(codespace)
      codespace.guid == most_recently_started_codespace_guid
    end

    def codespace_stopped(codespace)
      if codespace_most_recently_started?(codespace)
        ActiveRecord::Base.connected_to(role: :writing) { Codespaces::Kv.store.del(cache_key) }
      end
    end

    private

    def most_recently_started_codespace_guid
      Codespaces::Kv.store.get(cache_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def cache_key
      "codespaces-most-recent-start-#{@user.id}"
    end
  end
end
