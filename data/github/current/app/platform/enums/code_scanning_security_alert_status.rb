# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CodeScanningSecurityAlertStatus < Platform::Enums::Base
      description "The status of the code scanning security alert."

      value "OPEN", "The alert is open.", value: "open"
      value "FIXED", "The alert has been fixed.", value: "fixed"
      value "DISMISSED", "The alert has been dismissed.", value: "dismissed"
    end
  end
end
