# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::SubheadComponent < ApplicationComponent
  def initialize(subhead_text:, repo:, repo_owner:)
    @subhead_text = subhead_text
    @repo = repo
    @repo_owner = repo_owner
  end

  private

  attr_reader :subhead_text, :repo, :repo_owner
end
