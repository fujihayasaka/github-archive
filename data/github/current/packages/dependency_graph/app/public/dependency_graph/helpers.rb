# typed: strict
# frozen_string_literal: true


module DependencyGraph
  module Helpers
    extend T::Helpers

    abstract!

    sig { returns(T::Array[T.class_of(ApplicationJob)]) }
    def self.abstract_job_classes
      [
        BaseFindReposJob,
      ]
    end
  end
end
