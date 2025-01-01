# typed: true
# frozen_string_literal: true

module Workbench::User::Dependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  sig { returns(T::Boolean) }
  def spark_workbench_preview_enabled?
    T.bind(self, ::User)

    self.spark_enabled?
  end
end
