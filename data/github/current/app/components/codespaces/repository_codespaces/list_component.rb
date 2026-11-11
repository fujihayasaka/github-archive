# typed: true
# frozen_string_literal: true

class Codespaces::RepositoryCodespaces::ListComponent < ApplicationComponent
  include CodespacesHelper

  attr_reader :query, :repository

  delegate :user_feature_enabled?, to: :helpers

  def initialize(query:, repository:)
    @query = query
    @repository = repository
  end

  def codespaces_data
    query.codespaces.map { |codespace| generate_codespace_metadata(codespace) }
  end

  private

  def generate_codespace_metadata(codespace)
    usage_result = codespace_usage(codespace)
    {
      codespace: codespace,
      usage_allowed: usage_result.allowed?,
      show_editor_links: usage_result.allowed?,
      needs_machine_type_change: usage_result.disallowed_by_machine_policy?,
      needs_base_image_change: usage_result.disallowed_by_image_policy?,
      delete_confirmation_message: delete_confirmation_message(codespace),
      repository_policy: query.repository_policy(repository: codespace.repository, pull_request: codespace.pull_request),
    }
  end

  def delete_confirmation_message(codespace)
    if codespace.has_unpushed_changes?
      "#{codespace.safe_display_name} has unpushed changes, are you sure you want to delete?"
    else
      "Are you sure you want to delete #{codespace.safe_display_name}?"
    end
  end
end
