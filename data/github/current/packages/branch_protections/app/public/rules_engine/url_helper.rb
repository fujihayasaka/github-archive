# typed: strict
# frozen_string_literal: true

module RulesEngine
  module UrlHelper

    sig { params(actor: T.any(Bot, User)).returns(String) }
    def self.actor_path(actor)
      if actor.is_a?(Bot)
        # Pulled from app/helpers/url_helper.rb#user_path which cannot easily be used here
        "/#{actor.to_param}"
      else
        UrlHelpers.user_path(actor)
      end
    end
  end
end
