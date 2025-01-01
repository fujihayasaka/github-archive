# frozen_string_literal: true

def generate_ecdsa_key
  OpenSSL::PKey::EC.generate("prime256v1")
end

def get_base64_encoded_public_key(private_key)
  Base64.strict_encode64(private_key.public_to_pem)
end

def generate_ecdsa_fingerprint(encoded_key)
  decoded = Base64.strict_decode64(encoded_key)
  hash = Digest::SHA256.digest(decoded)
  fingerprint = Base64.strict_encode64(hash)
  # The authnd Go code omits base64 padding by using base64.RawStdEncoding
  # see https://github.com/github/authnd/blob/8a1941c9ec2f0686c51af54660318d5d533ac63e/client/token_verifier.go#L101-L111
  # None of the methods in Ruby's Base64 module seem to do this, so we have to do it manually.
  fingerprint.sub(/={0,2}$/, "") # remove trailing padding
end

def generate_jwt(payload, private_key, fingerprint)
  JWT.encode(payload, private_key, "ES256", { kid: fingerprint, typ: "jwt" })
end
