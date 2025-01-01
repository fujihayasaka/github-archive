# typed: true
# frozen_string_literal: true

module GitHub
  MAX_REF_LENGTH = 255
  NULL_OID  = ("0" * 40)
  NULL_MODE = ("0" * 6)
  TREE_MODE = "040000"
  UNKNOWN_REF_NAME = "refs/__gh__/UNKNOWN"
  PENDING_OID = "PENDING"

  EMPTY_TREE_OID = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

  SHA_LIKE_REF_NAME = /\Arefs\/(heads|tags)\/([0-9a-f]{40}(\/.*)?)\z/

  REFS_PREFIX_REF_NAME = /\Arefs\/(heads|tags)\/(refs\/.*)\z/
end
