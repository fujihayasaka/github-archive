# typed: true
# frozen_string_literal: true

module Codespaces
  class HardDelete < DeleteBase

    private

    def delete_environment_from_service
      client.hard_delete_environment(codespace.guid)
    end

    sig { returns(Codespace) }
    def delete_codespace
      codespace.destroy!
    end
  end
end
