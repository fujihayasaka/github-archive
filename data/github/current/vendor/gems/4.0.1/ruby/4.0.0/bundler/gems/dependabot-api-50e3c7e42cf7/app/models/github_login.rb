# frozen_string_literal: true

class GitHubLogin < ActiveRecord::Type::String
  def cast(login)
    strip_shortcode_in_proxima(login)
  end

  def serialize(login)
    strip_shortcode_in_proxima(login)
  end

  def deserialize(login)
    strip_shortcode_in_proxima(login)
  end

  private

  def strip_shortcode_in_proxima(login)
    return login unless Dependabot.proxima?

    username, _shortcode = login.split("_")
    username
  end
end
