# typed: true
# frozen_string_literal: true

module Repos::CodeScanning::ToolStatus
  class AbstractController < AbstractRepositoryController
    abstract!

    include GitHub::Memoizer
    include CodeScanning::ControllerAccessChecks

    private

    def default_branch_required
      render_404 if current_repository.default_branch_ref.nil?
    end

    memoize def ref
      current_repository.default_branch_ref.qualified_name
    end

    memoize def tools
      response = GitHub::Turboscan.get_tool_status(
        repository_id: current_repository.id,
        ref: ref,
      )

      raise ActionController::RoutingError.new("Turboscan response was nil") if response.nil?
      raise StandardError.new(response.error&.msg) if response.error.present?
      raise ActionController::RoutingError.new("Turboscan response was missing data") if response.data.nil?

      T.must(response.data).tools
    end

    memoize def workflows
      CodeScanning::Status.fetch_workflows(current_repository, CodeScanning::Status.workflow_paths(tools))
    end

    sig { returns(CodeScanning::Status::Messages) }
    memoize def messages
      CodeScanning::Status.messages(current_repository, tools, workflows)
    end
  end
end
