# frozen_string_literal: true

# You must have OpenSSL installed to ensure safe amounts of entropy for
# SecureRandom. Install openssl and ensure your Ruby is built with it.
require "openssl"
# Lets make sure OpenSSL::Random is available by calling it
# See also https://github.com/github/github/pull/5958#issuecomment-8444115
OpenSSL::Random
