# frozen_string_literal: true

class RepoSerializer < ActiveModel::Serializer
  attributes :id, :github_id, :name, :installation_state, :private,
             :github_url, :primary_language, :default_branch, :using_config_file
  attribute :config_file_path, if: -> { object.using_config_file? }

  has_many :active_update_configs, key: :update_configs
  has_one :account

  def installation_state
    return "inactive" unless object.id

    object.active_update_configs.any? ? "active" : "inactive"
  end

  def id
    object.github_id
  end

  def using_config_file
    object.using_config_file?
  end
end
