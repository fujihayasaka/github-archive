# typed: true
# frozen_string_literal: true

class OauthApplicationTransfers::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :transfer

  delegate :application, :id, :requester, :target, to: :transfer

  delegate :authorizations, :description, :key, :name, :url, :user, to: :application
end
