# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# This module is shared logic for storing and retrieving whether a codespace max_retention_period or max_idle_timeout
# has been overriden by an org policy. This information is passed onto the user.
module Codespaces
  module PolicyOverrideStorage
    extend T::Helpers

    requires_ancestor { Kernel }

    def toggle_has_override!(has_override, codespace_id)
      return unless codespace_id

      if has_override
        set_has_override_key!(codespace_id)
      else
        delete_has_override_key!(codespace_id)
      end
    end

    def delete_has_override_key!(codespace_id)
      return unless codespace_id

      ActiveRecord::Base.connected_to(role: :writing) do
        Codespaces::Kv.store.del(override_key(codespace_id))
      end
    end

    def set_has_override_key!(codespace_id)
      return unless codespace_id

      ActiveRecord::Base.connected_to(role: :writing) do
        Codespaces::Kv.store.setnx(override_key(codespace_id), "true")
      end
    end

    def has_override?(codespace_id)
      Codespaces::Kv.store.exists(override_key(codespace_id)).value!
    end

    def override_key(_)
      raise "must be implemented on subclass"
    end
  end
end
