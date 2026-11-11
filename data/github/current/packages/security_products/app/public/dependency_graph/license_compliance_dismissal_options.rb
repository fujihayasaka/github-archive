# typed: strict
# frozen_string_literal: true

module DependencyGraph
  module LicenseComplianceDismissalOptions
    DISMISSAL_OPTIONS = T.let([
      { value: "AMENDMENT", label: "Amendment", description: "The license policy should permit the use of this package or its license." },
      { value: "PRIVATE_PACKAGE", label: "Private package", description: "The component is internal code, which does not have upstream licensing." },
      { value: "INACCURATE", label: "Inaccurate", description: "The license shown in the alert does not match the actual license." },
    ], T::Array[{ value: String, label: String, description: String }])

    DISMISSAL_REASON_TO_CLOSURE_REASON = T.let({
      "AMENDMENT" => :CLOSURE_REASON_AMENDMENT,
      "PRIVATE_PACKAGE" => :CLOSURE_REASON_PRIVATE_PACKAGE,
      "INACCURATE" => :CLOSURE_REASON_INACCURATE_LICENSE,
    }.freeze, T::Hash[String, Symbol])

    CLOSURE_REASON_TO_LABEL = T.let({
      "CLOSURE_REASON_AMENDMENT" => "amendment",
      "CLOSURE_REASON_PRIVATE_PACKAGE" => "private package",
      "CLOSURE_REASON_INACCURATE_LICENSE" => "inaccurate license",
      "CLOSURE_REASON_POLICY_EDITED" => "policy edited",
      "CLOSURE_REASON_FIXED" => "fixed",
    }.freeze, T::Hash[String, String])

    sig { params(reason: String).returns(T::Boolean) }
    def self.valid_dismissal_reason?(reason)
      DISMISSAL_REASON_TO_CLOSURE_REASON.key?(reason)
    end

    sig { params(reason: String).returns(T.nilable(Symbol)) }
    def self.closure_reason_for(reason)
      DISMISSAL_REASON_TO_CLOSURE_REASON[reason]
    end

    sig { params(closure_reason: T.any(Symbol, String)).returns(T.nilable(String)) }
    def self.label_for_closure_reason(closure_reason)
      CLOSURE_REASON_TO_LABEL[closure_reason.to_s]
    end
  end
end
