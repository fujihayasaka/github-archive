# typed: true
# frozen_string_literal: true

class User
  # This class creates a Flipper Actor based on the current_visitor derived: app/controllers/application_controller.rb:1242
  # current_visitor sets cookies["_octo"] which you can access and then add to the desired flag

  # This is useful for enabling features for logged out users.

  # This is a common use case for the New User Experience team, where we often need to test
  # features before user creation like the new user sign up form

  # Register this current visitor actor on a feature in devtools by performing the following steps:
  #  1. Find your current visitor id by looking at your cookies for value of "_octo"
  #       This typically looks like: "GH1.1.1234.1234"
  #  1. Find your feature that you want to add future users to (:my_feature_name in this example)
  #  2. Choose Flipper ID as the actor type
  #  3. Enter User::CurrentVisitorActor:currentuserid (current visitor id from step #1)
  #  4. Now, visiting dotcom with the current visitor id from step #1 as the value of cookies["_octo"] will be in the flag logged in or logged out

  class CurrentVisitorActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    attr_reader :flipper_id

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def self.from_current_visitor(current_visitor_id)
      new(current_visitor_id)
    end

    def initialize(actor_id)
      @flipper_id = "#{self.class.name}:#{actor_id}"
      @vexi_id = "#{self.class.name}:#{actor_id}"
    end

    def to_s
      vexi_id
    end

    def vexi_id
      @vexi_id
    end
  end
end
