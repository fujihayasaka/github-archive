# typed: true
# frozen_string_literal: true

module Stafftools::ApplicationsHelper
  # Determines fragment exemption status for an application, accounting for
  # optimistic flash overrides after stafftools toggles (vexi writes are
  # eventually consistent across workers).
  def app_fragment_exempt?(app)
    f = T.unsafe(self).flash
    if f.key?(:oauth_fragment_exempt_override)
      f[:oauth_fragment_exempt_override]
    else
      app.oauth_fragment_exempt?
    end
  end
end
