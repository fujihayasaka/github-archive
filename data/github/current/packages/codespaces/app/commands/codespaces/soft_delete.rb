# typed: true
# frozen_string_literal: true

module Codespaces
  class SoftDelete < DeleteBase

    private

    def delete_environment_from_service
      client.delete_environment(codespace.guid)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def delete_codespace
      GitHub.dogstats.increment("codespaces_soft_delete.count", tags: ["reason:#{reason}"])
      codespace.soft_delete(reason)
    end
  end
end
