# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::NotifyOptionsComponent < ApplicationComponent
  def initialize(repo:, users_to_notify:, teams_to_notify:)
    @repo = repo
    @users_to_notify = users_to_notify
    @teams_to_notify = teams_to_notify
  end

  private

  attr_reader :repo, :users_to_notify, :teams_to_notify
end
