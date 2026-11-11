# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl
  define_access :create_agent_tasks do |access|
    access.ensure_context :resource
    access.allow :repo_agent_tasks_writer
  end

  define_access :read_agent_tasks do |access|
    access.ensure_context :resource
    access.allow :repo_agent_tasks_reader
  end
end
