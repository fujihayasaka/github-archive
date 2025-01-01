# typed: true
# frozen_string_literal: true

class Stafftools::NewsiesSettings
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def participating
    humanize settings.participating_settings
  end

  def subscribed
    humanize settings.subscribed_settings
  end

  private

  def settings
    @settings ||= GitHub.newsies.settings(user)
  end

  def humanize(data)
    return "none" if data.empty?
    data.sort.join ", "
  end

end
