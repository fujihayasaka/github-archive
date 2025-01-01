# typed: strict
# frozen_string_literal: true

##
### Tests for this are at: packages/spark_runtime/test/public/spark_runtime/naming_test.rb
##

module SparkRuntime
  class Naming

    # This method is intended for untended generation of an app name by the agent.
    # We can't revise or block on error, so we need to try to get something that
    # will pass uniqueness. Current approach is a short word suffix, checked for
    # uniqueness in the DB.
    #
    # Usage that is dealing strictly with user input where we can give errors instead
    # should be using convert_name.
    sig { params(user: User, name: String).returns(String) }
    def self.generate_unique_app_name(user, name)
      name = self.convert_name(name)

      already_exists = Spark::RuntimeApp.where(user_id: user.id, friendly_name: name).exists?
      return name unless already_exists

      # Our suffixes will be 5 characters, so trim up.
      # Then apply conversion again to handle hyphen ending.
      name = convert_name(T.must(name[0..14]))

      existing = Spark::RuntimeApp
        .where(user_id: user.id)
        .where("friendly_name LIKE ?", "#{name}%")
        .where.not(friendly_name: name)
        .pluck(:friendly_name)

      candidates = suffixes.map { |suff| "#{name}-#{suff}" }
      candidates -= existing
      candidate = candidates.sample

      # Silly to_s because Sorbet thinks it might be an array which it isn't
      return candidate.to_s if candidate

      raise ArgumentError, "No unique name found for #{name} available"
    end

    # convert_name is intended to do a precise conversion from a user-supplied name
    # to a friendly name appropriate for domain usage. It will _not_ attempt
    # to dedup or otherwise generate suffixes like generate_unique_app_name.
    #
    # It's intended to be used for taking user entered input (i.e. settings)
    # not AI generation where we want to always find an okay name.
    sig { params(name: String).returns(String) }
    def self.convert_name(name)
      # remove leading and trailing spaces
      name = name.strip
      # replace spaces with hyphens
      name = name.gsub(/\s+/, "-")
      # remove special characters
      name = name.gsub(/[^a-zA-Z0-9-]/, "")
      # convert to lowercase
      name = name.downcase
      # remove consecutive hyphens recursively
      name = name.gsub(/-[-]+/, "-")

      # if the name starts with any hypens, remove them
      name = name.sub(/^-+/, "")

      # limit to 20 characters
      name = T.must(name[0..19])

      # if the name ends with any hypens, remove them
      name = name.sub(/-+$/, "")

      name
    end

    # This method is intended to generate a unique and conforming user name for a user who may not
    # otherwise already be compliant with the ACA naming requirements.
    #
    # It should generate a name that is unique to the user, and will not conflict with any existing
    # user names in the system.
    #
    sig { params(name: String).returns(String) }
    def self.generate_unique_user_name(name)
      # convert underscores to hyphens (valid in enterprise)
      name = name.gsub(/_+/, "-")
      # remove special characters
      name = name.gsub(/[^a-zA-Z0-9-]/, "")
      # convert to lowercase
      name = name.downcase
      # remove consecutive hyphens
      name = name.gsub(/-[-]+/, "-")
      # if the name starts with any hyphens, remove them
      name = name.sub(/^-+/, "")
      # limit to 20 characters
      name = T.must(name[0..19])
      # if the name ends with any hyphens, remove them
      name = name.sub(/-+$/, "")

      # Check if the cleaned name is already ACA compliant and unique
      return name if is_aca_compliant_name?(name) && !Spark::RuntimeAppOwner.exists?(deploy_login: name)

      # Now we need to generate numerical variations
      # Start with the base name, ensuring it fits with a number suffix
      # Reserve space for up to 3 digits (e.g., "123")
      name = T.must(name[0..16])

      existing = Spark::RuntimeAppOwner
        .where("deploy_login LIKE ?", "#{name}%")
        .pluck(:deploy_login)

      candidates = numerical_suffixes.map { |suff| "#{name}#{suff}" }
      candidates -= existing
      candidate = candidates.sample

      # Silly to_s because Sorbet thinks it might be an array which it isn't
      return candidate.to_s if candidate

      # If we still haven't found a unique name, something is very wrong
      raise ArgumentError, "Unable to generate unique ACA-compliant username for #{name}"
    end

    # This method is intended to check if a name is compliant with the ACA naming requirements.
    sig { params(name: String).returns(T::Boolean) }
    def self.is_aca_compliant_name?(name)
      # Check if the name is empty or nil
      return false if name.strip.empty?

      # Check if the name is too long
      return false if name.length > 20

      # Check if the name contains only alphanumeric characters and hyphens
      return false unless name.match?(/\A[a-zA-Z0-9-]+\z/)

      # Check if the name starts or ends with a hyphen
      return false if name.start_with?("-") || name.end_with?("-")

      # Check if the name contains consecutive hyphens
      return false if name.include?("--")

      return false if %w(users user data management).include?(name)

      # If all checks pass, the name is compliant
      true
    end

    # These suffixes will be used to generate more unique names in the face
    # of collisions. We keep them short because of our 20 character limit.
    # We use a method here to allow for stubbing in tests
    sig { returns(T::Array[String]) }
    def self.suffixes
      %w(
        able
        also
        area
        atom
        away
        bake
        ball
        band
        bank
        bell
        best
        bike
        bird
        boat
        bold
        book
        calm
        card
        care
        cart
        chat
        chip
        clay
        clip
        club
        coat
        cold
        cool
        cord
        core
        data
        deck
        deep
        deer
        desk
        dime
        dive
        door
        drop
        drum
        duck
        echo
        edge
        edit
        even
        exit
        fair
        fall
        farm
        fast
        file
        fill
        film
        fish
        flag
        flat
        flip
        flow
        foam
        fold
        food
        foot
        form
        frog
        gain
        game
        gift
        glow
        goat
        gold
        golf
        good
        grid
        grip
        grow
        hand
        heal
        help
        hero
        hold
        hope
        huge
        idea
        iron
        item
        join
        jump
        keep
        kind
        know
        lamp
        land
        last
        leaf
        life
        lift
        line
        link
        lion
        list
        live
        load
        lock
        long
        look
        loop
        love
        luck
        mail
        main
        make
        mark
        mask
        meet
        mile
        mind
        mint
        moon
        move
        must
        name
        need
        nest
        news
        next
        note
        open
        path
        peak
        pick
        plan
        play
        plot
        port
        pull
        pure
        quit
        rain
        read
        real
        rest
        rice
        ride
        ring
        rise
        road
        rock
        root
        rope
        rule
        safe
        sale
        sand
        save
        seat
        self
        send
        ship
        shop
        show
        side
        sign
        slow
        snow
        soft
        soil
        song
        sort
        spin
        star
        stay
        step
        swim
        tall
        task
        team
        text
        time
        tire
        tone
        tool
        town
        tree
        trip
        true
        turn
        type
        unit
        user
        view
        walk
        wall
        want
        warm
        wash
        wave
        week
        well
        west
        wide
        wild
        will
        wind
        wing
        wire
        wise
        wood
        word
        work
        yard
        year
        your
        zest
        zone
      )
    end

    sig { returns(T::Array[String]) }
    def self.numerical_suffixes
      (1..999).map(&:to_s)
    end
  end
end
