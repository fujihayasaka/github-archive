# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class AuthorizePortForwarding < Command
    VISIBILITY_ORG = "org"
    VISIBILITY_REPO = "repo"
    VISIBILITY_PRIVATE = "private"

    attr_reader :user, :codespace, :visibility

    def initialize(user:, codespace:, visibility: nil)
      @user = user
      @codespace = codespace
      @visibility = visibility
    end

    def perform
      [can_access_port?, scope]
    end

    private

    def can_access_port?
      return false unless valid_visibility(visibility) && codespace.repository.present?
      # If you created the codespace, you can always access the ports.
      # But what if you created a codespace in an organization that you
      # may have left in the future? In this case, this will technically return
      # true when it shouldn't. However, because we make the billable owner = nil
      # on all the codespaces that belong to you within that org, Codespaces#usage_allowed?
      # let you access the codespace or any of its ports. If in the future we allow codespace
      # sharing and ownership transfers, then this may certainly need to be rewritten.
      owner = codespace.repository.owner
      codespace.owner == user || (visibility == VISIBILITY_ORG && owner.is_a?(Organization) && owner.member?(user))
    end

    def scope
      return Codespaces::VscsClient::PRIVATE_SCOPE if visibility.nil?
      "connect:#{visibility}-ports"
    end

    def valid_visibility(visibility)
      return true if visibility.nil? # temporary
      [VISIBILITY_ORG, VISIBILITY_REPO, VISIBILITY_PRIVATE].include?(visibility)
    end
  end
end
