# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module CodeQLVariantAnalysis
      # Details for Memory Alpha storage for variant analysis
      attr_accessor :codeql_variant_analysis_memory_alpha_bucket
      attr_accessor :codeql_variant_analysis_azure_storage_account
      attr_accessor :codeql_variant_analysis_memory_alpha_secret
      attr_accessor :codeql_variant_analysis_azure_container
    end
  end

  extend Config::CodeQLVariantAnalysis
end
