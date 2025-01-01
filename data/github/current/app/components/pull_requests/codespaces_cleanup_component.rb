# typed: true
# frozen_string_literal: true

class PullRequests::CodespacesCleanupComponent < ApplicationComponent
  attr_reader :pull, :cleanup_did_error, :head_label, :codespaces

  def initialize(pull:, cleanup_did_error:, head_label: nil, codespaces:)
    @pull = pull
    @cleanup_did_error = cleanup_did_error
    @head_label = head_label
    @codespaces = codespaces
  end

  def render?
    codespaces.any?
  end
end
