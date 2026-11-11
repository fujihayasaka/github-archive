# typed: strict
# frozen_string_literal: true

module Copilot
  # Unified token type accepted by downstream Copilot integrations. Represents either a
  # decrypted (ready-to-use) token value or an encrypted token that can still be passed
  # through to APIs expecting the union.
  Token = T.type_alias { T.any(DecryptedToken, EncryptedToken) }
end
