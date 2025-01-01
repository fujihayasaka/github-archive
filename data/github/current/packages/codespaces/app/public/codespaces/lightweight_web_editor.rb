# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module LightweightWebEditor

    # Routes that github.dev knows how to handle.
    # first level is controller names, second level is action names.
    IMPLEMENTED_ROUTES = {
      "files" => {
        "disambiguate" => true,
        "overview" => true,
      }.freeze,
      "pull_requests" => {
        "show" => true,
        "commits" => true,
        "checks" => true,
        "files" => true,
      }.freeze,
      "pull_requests_fragments" => {
        "pull_request_layout" => true,
      }.freeze,
      "blob" => {
        "show" => true
      }.freeze,
      "tree" => {
        "show" => true
      }.freeze
    }.freeze

    def self.partner_info(user:, token:, host:)
      GenerateWebEditorPartnerInfo.call(user: user, token: token, host: host)
    end

    # Does github.dev know how to interpret URLs for the given controller action?
    # i.e. can we open it in github.dev by changing the TLD from '.com' to '.dev'?
    def self.can_handle_route?(controller_name:, action_name:)
      return false unless controller = IMPLEMENTED_ROUTES[controller_name]
      controller[action_name]
    end

    def self.revoke_all_tokens(user:, timeout:, entry_point:)
      RevokeWebEditorTokens.call(user: user, timeout: timeout, entry_point: entry_point)
    end
  end
end
