# typed: strict
# frozen_string_literal: true

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
    def self.generate_unique_name(user, name)
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

    # convert_name is intended to do a precise conversion from a user name
    # to a friendly name appropriate for domain usage. It will _not_ attempt
    # to dedup or otherwise generate suffixes like generate_unique_name.
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
  end
end
