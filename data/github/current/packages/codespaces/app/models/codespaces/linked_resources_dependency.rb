# typed: true
# frozen_string_literal: true

module Codespaces
  module LinkedResourcesDependency
    extend T::Helpers

    sig { returns(T::Hash[String, T.untyped]) }
    def linked_resources
      super || {}
    end

    sig { params(value: T.nilable(T::Hash[String, T.untyped])).returns(T.nilable(T::Hash[String, T.untyped])) }
    def linked_resources=(value)
      super(value)
    end

    sig { returns(T.nilable(String)) }
    def spark_workbench_id
      linked_resources["spark_workbench_id"]
    end

    sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
    def spark_workbench_id=(value)
      self.linked_resources = if value.nil?
        self.linked_resources.except("spark_workbench_id")
      else
        self.linked_resources.merge("spark_workbench_id" => value)
      end

      linked_resources["spark_workbench_id"]
    end
  end
end
