# typed: true
# frozen_string_literal: true

class Codespaces::IndexListComponent < ApplicationComponent
  include CodespacesHelper

  attr_reader :query

  def initialize(query:, repository_id: nil, unpublished: false)
    @query = query
    @billable_cache = {}
    @repository_id = repository_id
    @unpublished = unpublished
  end

  def user_owns_codespaces?
    query_codespaces.any? { |codespace| codespace.billable_owner == @query.current_user }
  end

  def all_codespaces_for(billable_owner)
    all_codespaces.select { |metadata| metadata[:codespace].billable_owner == billable_owner }.each_with_object({})
  end

  def other_billable_owners
    query_codespaces.map(&:billable_owner).uniq - [@query.current_user]
  end

  private

  memoize def query_codespaces
    codespaces = query.codespaces

    if @unpublished
      codespaces.select!(&:unpublished?)
    end

    if @repository_id
      codespaces.select! { |c| c.repository_id == @repository_id }
    end

    codespaces
  end

  # All codespaces for the user, including published and unpublished
  memoize def all_codespaces
    query_codespaces.map { |codespace| generate_codespace_metadata(codespace) }
  end

  memoize def build_codespace
    @query.build_codespace
  end

  def generate_codespace_metadata(codespace)
    GitHub.tracer.in_span("codespaces/index_list_component#generate_codespace_metadata", kind: :internal) do |_span|
      usage_result = GitHub.tracer.in_span("codespaces/index_list_component/generate_codespace_metadata#usage", kind: :internal) do |_span|
        codespace_usage(codespace)
      end
      repository_policy = GitHub.tracer.in_span("codespaces/index_list_component/generate_codespace_metadata#repository_policy", kind: :internal) do |_span|
        pull_request = with_database_error_fallback(fallback: nil) { codespace.pull_request }
        query.repository_policy(repository: codespace.repository, pull_request: pull_request)
      end
      {
        codespace: codespace,
        usage_allowed: usage_result.allowed?,
        show_editor_links: usage_result.allowed?,
        needs_machine_type_change: usage_result.disallowed_by_machine_policy?,
        needs_base_image_change: usage_result.disallowed_by_image_policy?,
        delete_confirmation_message: delete_confirmation_message(codespace),
        repository_policy: repository_policy
      }
    end
  end

  def delete_confirmation_message(codespace)
    if codespace.has_unpushed_changes?
      "#{codespace.safe_display_name} has unpushed changes, are you sure you want to delete?"
    else
      "Are you sure you want to delete #{codespace.safe_display_name}?"
    end
  end
end
