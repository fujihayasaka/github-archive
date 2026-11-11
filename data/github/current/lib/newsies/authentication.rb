# typed: true
# frozen_string_literal: true

module Newsies
  class Authentication
    def self.token(action, user, id, extra_data = {})
      user.signed_auth_token(scope: token_scope(action),
        expires: 10.years.from_now, data: { "id" => id }.merge(extra_data))
    end

    def self.user_and_id_from_token(type, token)
      parsed = parse_token type, token
      if parsed.valid?
        GitHub.dogstats.increment "newsies.authentication.#{type}_signed_auth_token"
        [parsed.user, parsed.data["id"], parsed.data.except("id")]
      else
        [nil, nil, nil]
      end
    end

    def self.valid_unsubscribe_token?(token, user, repository)
      parsed = parse_token :unsubscribe, token
      if parsed.user == user && parsed.data["id"] == repository.id
        true
      else
        false
      end
    end

    def self.parse_token(type, token)
      User.verify_signed_auth_token token: token, scope: token_scope(type)
    end
    private_class_method :parse_token

    def self.token_scope(action)
      "Newsies:#{action.to_s.capitalize}"
    end
    private_class_method :token_scope
  end
end
