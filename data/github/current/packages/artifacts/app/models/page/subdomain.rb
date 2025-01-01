# typed: false
# frozen_string_literal: true

class Page::Subdomain
  attr_reader :repository, :page, :owner

  # method used to create private pages subdomain name
  ADJECTIVES = %w[
    animated
    automatic
    bookish
    cautious
    congenial
    crispy
    cuddly
    curly
    didactic
    effective
    expert
    fantastic
    fictional
    fluffy
    friendly
    fuzzy
    glowing
    ideal
    improved
    jubilant
    laughing
    legendary
    literate
    miniature
    musical
    potential
    probable
    psychic
    redesigned
    refactored
    reimagined
    scaling
    shiny
    silver
    solid
    special
    studious
    stunning
    sturdy
    super
    supreme
    symmetrical
    turbo
    ubiquitous
    upgraded
    urban
    verbose
    vigilant
  ].freeze

  NOUNS = %w[
    adventure
    barnacle
    bassoon
    broccoli
    carnival
    chainsaw
    couscous
    disco
    dollop
    doodle
    engine
    enigma
    eureka
    fiesta
    fishstick
    fortnight
    funicular
    garbanzo
    giggle
    goggles
    guacamole
    guide
    happiness
    invention
    journey
    lamp
    meme
    memory
    pancake
    parakeet
    potato
    robot
    sniffle
    spoon
    spork
    succotash
    system
    telegram
    train
    tribble
    umbrella
    waddle
    waffle
    winner
  ].freeze

  HASHID_SETTINGS = {
    salt: "The universal answer is 42 grains of salt.",
    min_length: 5,
    alphabet: "abcdefghijklmnopqrstuvwxyz0123456789"
  }.freeze

  def initialize(repository:)
    @repository = repository
    @page = repository.page
    @owner = @repository.owner
  end

  def adjectives
    ADJECTIVES
  end

  def nouns
    NOUNS
  end

  def hashid_settings
    HASHID_SETTINGS
  end

  # Returns the appropriate subdomain value based on the environment
  # Proxima: nwo: "org/foo" => org-foo.pages.avocado.ghe.com
  # Dotcom:  nwo: "org/foo" => adjective-noun-hash.pages.github.io
  def value(make_unique: false)
    GitHub.multi_tenant_enterprise? ? self.for_proxima(make_unique: make_unique) : self.for_dotcom_private
  end

  # returns nil if the page doesn't exist yet, otherwise the subdomain without the tenant shortcode
  def default_proxima_display
    return if @page.subdomain.nil?
    @page.subdomain&.chomp("_#{@owner.business.shortcode}")
  end

  # Returns the repo name shortened to 63 characters and with invalid characters substituted for valid ones
  def normalized_repo
    @repository.name
      .gsub(" ", "-").split(/([ _-])/).map(&:downcase)
      .join
      .tr("_", "-")
      .tr(".", "-")
      .gsub(/\A\-+|\-+\z/, "")[0..63]
  end

  def subdomain_hash_id
    # This is not a hash and is not intended to be secure.
    hashids = Hashids.new(hashid_settings[:salt], hashid_settings[:min_length], hashid_settings[:alphabet])
    hashids.encode(@page.id)
  end

  # Deterministically generates a subdomain for a private page.
  # Must be deterministic so that it can be displayed in the UI before it is assigned in the database.
  # Also must be partially based on the repository name so that if the repo is renamed the subdomain will also change.
  def for_dotcom_private
    repo_name_component = Digest::SHA256.new(repository.name).hexdigest.to_i
    adjective = adjectives[(repo_name_component + @page.id) % adjectives.length]
    noun = nouns[repo_name_component % nouns.length]
    # For now, shorten to max length for a subdomain.
    # If ids get too long can always use an offset against page.id or shorten here and accept the risk of collisions.
    subdomain = "#{adjective}-#{noun}-#{subdomain_hash_id}"

    if subdomain.length > 64
      GitHub.dogstats.increment "pages.subdomain.too_long"
      subdomain = subdomain[0..63]
    end

    subdomain
  end

  private

  # Create a subdomain for Proxima
  #
  # Subdomains have a max length of 63 per IETF
  # The database includes the business shortcode, which does not count towards 63 char max
  # Adding a hash be necessary due to normalization process which substitutes some characters
  # LOGIN_MAX_LENGTH set in user model is a max of 39, leaving 24 chars for repo in worst case
  def for_proxima(make_unique: false)
    routable_subdomain = "#{owner.display_login}-#{normalized_repo}"[0..62]

    if make_unique
      hash = Digest::SHA256.hexdigest @repository.name
      routable_subdomain = "#{routable_subdomain[0..55]}-#{hash[0..5]}" # hash length is 7 (6 plus a dash)
    end

    "#{routable_subdomain}_#{page.shortcode}"
  end
end
