# typed: true
# frozen_string_literal: true

class Issue::Adapter::AppAdapter < Issue::Adapter::Base
  attr_reader :id
  attr_reader :name
  attr_reader :html_url
  attr_reader :logo_url

  def initialize(context, app:, logo_url_size: 40)
    super(context)

    @id = app.global_relay_id
    @name = app.name

    bot = context.users_by_id[app.bot_id]
    @html_url = Addressable::URI.parse("#{GitHub.url}/#{bot.to_param}").to_s
    @logo_url = app.preferred_avatar_url(size: logo_url_size)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
