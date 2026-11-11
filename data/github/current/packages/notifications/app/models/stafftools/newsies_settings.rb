# typed: true
# frozen_string_literal: true

class Stafftools::NewsiesSettings
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def participating
    humanize settings.participant
  end

  def subscribed
    humanize settings.watcher
  end

  private

  def settings
    @settings ||= Notifications::Settings.settings(user)
  end

  def humanize(setting)
    data = []
    data << "email" if setting.email
    data << "web" if setting.web

    return "none" if data.empty?
    data.sort.join ", "
  end

end
