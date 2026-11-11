# typed: true
# frozen_string_literal: true

class DsaExplanations
  class ValidationError < StandardError
  end

  class << self
    def email_partial_for_tos_reason(tos_reason)
      @@dsa_explanations ||= load_json
      filtered_explanations = @@dsa_explanations.select { |_, explanation| explanation["type"] == "tos_reason" }
      filtered_explanations.dig(tos_reason, "email_partial") || "our Acceptable Use Policies or Terms of Service."
    end

    def email_partial_for_dsa_source(dsa_source)
      @@dsa_explanations ||= load_json
      filtered_explanations = @@dsa_explanations.select { |_, explanation| explanation["type"] == "dsa_source" }
      filtered_explanations.dig(dsa_source, "email_partial") || "we reviewed your account"
    end

    private

    DSA_EXPLANATIONS_PATH = "config/health/trust_safety/dsa_explanations.json"

    def load_json
      file_path = Rails.root.join(DSA_EXPLANATIONS_PATH)
      GitHub::JSON.load(File.read(file_path))
    end
  end
end
