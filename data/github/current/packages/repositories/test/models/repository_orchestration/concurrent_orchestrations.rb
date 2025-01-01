# typed: true
# frozen_string_literal: true

module TestConcurrentOrchestrationModule
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { RepositoryOrchestration }

  included do
    T.bind(self, T.class_of(RepositoryOrchestration))

    job_start

    step :recurse do
      T.bind(self, TestConcurrentOrchestrationModule)

      return if depth >= 2

      orchestration = case depth
      when 0
        TestConcurrentOrchestrationChild.stop_after_step = :recurse
        TestConcurrentOrchestrationChild.create(repository: repository, data: { depth: 1 })
      when 1
        TestConcurrentOrchestrationGrandchild.stop_after_step = :recurse
        TestConcurrentOrchestrationGrandchild.create(repository: repository, data: { depth: 2 })
      end

      block_on_orchestration(orchestration)
    end

    step :finish do
      # no-op
    end

    def depth
      data[:depth]
    end
  end
end

class TestConcurrentOrchestration < RepositoryOrchestration
  include TestConcurrentOrchestrationModule
end

class TestConcurrentOrchestrationChild < RepositoryOrchestration
  include TestConcurrentOrchestrationModule
end

class TestConcurrentOrchestrationGrandchild < RepositoryOrchestration
  include TestConcurrentOrchestrationModule
end
