# typed: strict
# frozen_string_literal: true

module Spark
  class RuntimeAppDeploy < ApplicationRecord::Copilot
    self.table_name = "runtime_app_deploys"

    belongs_to :runtime_app, optional: false

    sig { returns(String) }
    def signed_url
      ::Workbench::ScanningBlobClient.get_signed_url(self, 60)
    end
  end
end
