# typed: true
# frozen_string_literal: true

require "elastomer"

postfix = "test" if Rails.env.test?
Elastomer.setup(postfix: postfix)

class ElastomerClient::Client::TimeoutError
  def failbot_context
    { app: "github-timeout" }
  end
end
