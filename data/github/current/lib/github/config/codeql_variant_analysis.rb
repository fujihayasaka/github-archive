# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module CodeQLVariantAnalysis
      # Details for Memory Alpha storage for variant analysis
      attr_accessor :codeql_variant_analysis_memory_alpha_bucket
      attr_accessor :codeql_variant_analysis_memory_alpha_key_id
      attr_accessor :codeql_variant_analysis_memory_alpha_access_key
      attr_accessor :codeql_variant_analysis_azure_bucket
    end
  end

  extend Config::CodeQLVariantAnalysis
end
