# typed: true
# frozen_string_literal: true

module Api::Serializer::DesktopDependency
  def avatar_token(avatar_token, options = {})
    {
      avatar_token: avatar_token,
    }
  end
end
