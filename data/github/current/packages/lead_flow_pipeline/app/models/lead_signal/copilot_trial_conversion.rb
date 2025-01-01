# typed: strict
# frozen_string_literal: true

# Represents when a user exits the Copilot trial through conversion to a paid plan.
module LeadSignal
  class CopilotTrialConversion < Base
    extend T::Sig
    extend T::Helpers

    sig { override.returns(String) }
    def campaign_name
      "CO-GHAI-Self-Service-Purchase-FY24-10Oct-30-CoPilot"
    end

    sig { override.returns(T::Hash[Symbol, String]) }
    def attributes
      {} # No additional attributes are needed for this signal
    end
  end
end
