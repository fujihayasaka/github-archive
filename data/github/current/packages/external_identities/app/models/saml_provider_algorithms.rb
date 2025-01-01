# typed: false
# frozen_string_literal: true

module SamlProviderAlgorithms

  # The USE_DEFAULT_ options provided here are so that ActiveRecord::Enum knows what
  # to do with the default value of 0. This will get re-written to the proper default key
  # in the before_validation callbacks.

  # https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-MessageAuthentication
  SIGNATURE_METHOD_MAPPING = {
    "USE_DEFAULT_SIGNATURE_MAPPING"                     => 0,
    "http://www.w3.org/2001/04/xmldsig-more#rsa-sha1"   => 160,
    "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256" => 256,
    "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384" => 384,
    "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512" => 512,
  }
  DEFAULT_SIGNATURE_METHOD = SIGNATURE_METHOD_MAPPING.key(256)

  # https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-MessageDigest
  DIGEST_METHOD_MAPPING = {
    "USE_DEFAULT_DIGEST_MAPPING"              => 0,
    "http://www.w3.org/2000/09/xmldsig#sha1"  => 160,
    "http://www.w3.org/2001/04/xmlenc#sha256" => 256,
    "http://www.w3.org/2001/04/xmlenc#sha384" => 384,
    "http://www.w3.org/2001/04/xmlenc#sha512" => 512,
  }
  DEFAULT_DIGEST_METHOD = DIGEST_METHOD_MAPPING.key(256)

  # https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-Block
  ENCRYPTION_METHOD_MAPPING = {
    "USE_DEFAULT_ENCRYPTION_MAPPING"                  => 0,
    "http://www.w3.org/2001/04/xmlenc#aes128-cbc"     => 128,
    "http://www.w3.org/2001/04/xmlenc#aes192-cbc"     => 192,
    "http://www.w3.org/2001/04/xmlenc#aes256-cbc"     => 256,
  }
  DEFAULT_ENCRYPTION_METHOD = ENCRYPTION_METHOD_MAPPING.key(256)

  # https://www.w3.org/TR/2002/REC-xmlenc-core-20021210/Overview.html#sec-Alg-KeyTransport
  KEY_TRANSPORT_METHOD_MAPPING = {
    "USE_DEFAULT_KEY_TRANSPORT_MAPPING"               => 0,
    "http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p" => 1,
  }
  DEFAULT_KEY_TRANSPORT_METHOD = KEY_TRANSPORT_METHOD_MAPPING.key(1)

  def self.included(base)
    base.enum :signature_method, SIGNATURE_METHOD_MAPPING
    base.enum :digest_method, DIGEST_METHOD_MAPPING
    base.enum :encryption_method, ENCRYPTION_METHOD_MAPPING
    base.enum :key_transport_method, KEY_TRANSPORT_METHOD_MAPPING
  end

  def set_default_signature_method
    return unless self.class.signature_methods[signature_method].zero?
    self.signature_method = DEFAULT_SIGNATURE_METHOD
  end

  def set_default_digest_method
    return unless self.class.digest_methods[digest_method].zero?
    self.digest_method = DEFAULT_DIGEST_METHOD
  end

  def set_default_encryption_method
    return unless self.class.encryption_methods[encryption_method].zero?
    self.encryption_method = DEFAULT_ENCRYPTION_METHOD
  end

  def set_default_key_transport_method
    return unless self.class.key_transport_methods[key_transport_method].zero?
    self.key_transport_method = DEFAULT_KEY_TRANSPORT_METHOD
  end
end
