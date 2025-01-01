# typed: strict
# frozen_string_literal: true

class Stafftools::Repositories::PullRequestOrchestrationsComponent < ApplicationComponent
  extend T::Sig

  sig { returns(String) }
  attr_reader :title

  sig { returns(T::Enumerable[PullRequestOrchestration]) }
  attr_reader :orchestrations

  sig { params(title: String, orchestrations: T::Enumerable[PullRequestOrchestration]).void }
  def initialize(title, orchestrations)
    @title = T.let(title, String)
    @orchestrations = T.let(orchestrations, T::Enumerable[PullRequestOrchestration])
  end

  sig { params(orchestration: PullRequestOrchestration).returns(String) }
  def orchestration_link(orchestration)
    link_to "##{orchestration.id}", gh_stafftools_repository_pull_request_orchestration_path(orchestration)
  end

  sig { params(state: String).returns(String) }
  def octicon_for_state(state)
    case state
    when "succeeded"
      render(Primer::Beta::Octicon.new(icon: :"check-circle", color: :success))
    when "failed"
      render(Primer::Beta::Octicon.new(icon: :"x-circle", color: :danger))
    when "created"
      render(Primer::Beta::Octicon.new(icon: :"circle", color: :muted))
    else
      render(Primer::Beta::Octicon.new(icon: :"question", color: :attention))
    end
  end

  sig { params(orchestration: PullRequestOrchestration).returns(String) }
  def orchestration_type(orchestration)
    orchestration.type.demodulize.to_s
  end
end
