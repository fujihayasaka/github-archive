# frozen_string_literal: true

# Support Fastly PURGE calls
# https://docs.fastly.com/api/purge#purge_3aa1d66ee81dbfed0b03deed0fa16a9a
Faraday::Connection::METHODS << :purge
