# typed: strict
# frozen_string_literal: true

module Marketplace
  extend T::Sig

  APPLY_FOR_PUBLISHER_VERIFICATION_DOCS = T.let("https://docs.github.com/developers/github-marketplace/applying-for-publisher-verification-for-your-organization".freeze, String)
end
