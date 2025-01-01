# typed: strict
# frozen_string_literal: true

module Spark
  class RuntimeAppDeploy < ApplicationRecord::Copilot
    self.table_name = "runtime_app_deploys"

    belongs_to :runtime_app, optional: false
  end
end
