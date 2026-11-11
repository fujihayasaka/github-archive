# frozen_string_literal: true

require "octolytics"

class Octolytics::Error
  def failbot_context
    { app: "github-octolytics" }
  end
end
