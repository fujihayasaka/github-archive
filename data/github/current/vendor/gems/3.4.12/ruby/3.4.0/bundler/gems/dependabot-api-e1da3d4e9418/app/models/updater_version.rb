# frozen_string_literal: true

class UpdaterVersion < ApplicationRecord
  enum env: { stage: "stage", prod: "prod" }

  validates :env, presence: true, inclusion: { in: envs.keys }
  validates :ecosystem, presence: true
  validates :version, presence: true

  def firecracker_image
    "#{version}-#{ecosystem}"
  end

  def actions_image
    "ghcr.io/dependabot/dependabot-updater-#{ecosystem}:#{version}"
  end
end
