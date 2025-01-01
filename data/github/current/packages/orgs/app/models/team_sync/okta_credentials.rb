# typed: true
# frozen_string_literal: true

module TeamSync
  class OktaCredentials
    include ActiveModel::Model

    validates :ssws_token, presence: true
    validates :url, presence: true, strict_host: true

    attr_accessor :ssws_token, :url
  end
end
