# typed: strict
# frozen_string_literal: true

module DependencyGraph
  module LicenseComplianceDismissalOptions
    DISMISSAL_OPTIONS = T.let([
      { value: "AMENDMENT", label: "Amendment", description: "Edit license policy to allow dependency" },
      { value: "PRIVATE_PACKAGE", label: "Private package", description: "Dependency is internal and does not require compliance review" },
      { value: "INACCURATE", label: "Inaccurate", description: "Detected license does not match actual license" },
    ], T::Array[{ value: String, label: String, description: String }])

    DISMISSAL_REASON_TO_CLOSURE_REASON = T.let({
      "AMENDMENT" => :CLOSURE_REASON_AMENDMENT,
      "PRIVATE_PACKAGE" => :CLOSURE_REASON_PRIVATE_PACKAGE,
      "INACCURATE" => :CLOSURE_REASON_INACCURATE_LICENSE,
    }.freeze, T::Hash[String, Symbol])

    sig { params(reason: String).returns(T::Boolean) }
    def self.valid_dismissal_reason?(reason)
      DISMISSAL_REASON_TO_CLOSURE_REASON.key?(reason)
    end

    sig { params(reason: String).returns(T.nilable(Symbol)) }
    def self.closure_reason_for(reason)
      DISMISSAL_REASON_TO_CLOSURE_REASON[reason]
    end
  end
end
