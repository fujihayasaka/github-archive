# typed: true
# frozen_string_literal: true

class EditRepositories::AdminScreen::DeployKeysView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :selected_key

  def initialize(pubkey)
    @selected_key = pubkey
  end

  def permissions_text(deploy_key)
    " — " + (deploy_key.read_only? ? "Read-only" : "Read/write")
  end
end
