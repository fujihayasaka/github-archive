# typed: false
# frozen_string_literal: true

module SuggestedUsernamesHelper
  MAX_SUGGESTED_USERNAME_ATTEMPTS = 15
  MAX_SUGGESTED_USERNAMES = 3
  DESCRIPTORS_MIN = 2
  RANDOM_NUMBER_MIN = 1
  RANDOM_MAX = 1000
  EVENT_ACTIONS = {
    used: "used",
    success: "success",
    failed: "failed",
    random_number_generation_success: "random_number_generation_success",
    random_number_generation_failed: "random_number_generation_failed",
    descriptor_generation_success: "descriptor_generation_success",
    descriptor_generation_failed: "descriptor_generation_failed",
  }.freeze

  DESCRIPTORS = %w[
    dev
    code
    coder
    tech
    design
    lab
    eng
    prog
    arch
    create
    creator
    maker
    spec
    commits
    source
    cpu
    ai
    debug
    web
    bot
    art
    bit
    byte
    hash
    sudo
    pixel
    star
    cmyk
    rgb
    jpg
    png
    svg
    gif
    hub
    lang
    dot
    sketch
    cell
    glitch
    wq
    cmd
    ctrl
    alt
    del
    stack
    afk
    blip
    beep
    boop
    lgtm
    ship-it
    cloud
    sys
    ux
    ui
    oss
    collab
    max
    hue
    ops
    dotcom
    a11y
    droid
    crypto
    cyber
    netizen
  ]

  # Public:
  # Returns if we should suggest usernames.
  # Historically we've changed the rules around what is allowed.
  # For example "a-" would not be allowed now because it ends in a hyphen, but it was allowed at some point.
  # To make sure we're not suggesting usernames that are taken but invalid with current rules
  # we only make suggestions if the only error is that it is a taken username
  #
  # login_errors: array of error messages on user
  # suggest_usernames_param: boolean from request
  #
  # Returns boolean
  def suggest_usernames?(login_errors:, suggest_usernames_param:)
    login_errors.count == 1 && login_errors.any? { |e| e.match(User::NOT_UNIQUE_LOGIN_MESSAGE) } && suggest_usernames_param
  end

  # Public:
  # Attempt to generate username suggestions using random numbers and descriptors
  #
  # base_username - String representing the taken username
  #
  # Publishes events to hydro for success
  # Returns an array of suggested usernames or an empty array
  def get_username_suggestions(base_username:)
    descriptor_usernames = descriptor_usernames(base_username: base_username)
    random_number_usernames = random_number_usernames(base_username: base_username)

    all_suggestions = descriptor_usernames.sample(DESCRIPTORS_MIN)

    # Fill in rest of suggestions with random number usernames
    random_number_usernames_needed = MAX_SUGGESTED_USERNAMES - all_suggestions.count
    all_suggestions += random_number_usernames.sample(random_number_usernames_needed)

    if all_suggestions.count == MAX_SUGGESTED_USERNAMES
      publish_suggested_username_event(suggestion_count: all_suggestions.count, action: EVENT_ACTIONS[:success])
      all_suggestions
    else
      publish_suggested_username_event(suggestion_count: all_suggestions.count, action: EVENT_ACTIONS[:failed])
      []
    end
  end

  def suggested_username_used?(username:, suggested_usernames:)
    return false unless suggested_usernames.present?
    suggested_usernames.include?(username)
  end

  def publish_suggested_username_event(user_id: nil, login: nil, suggestion_count:, action:)
    return unless EVENT_ACTIONS.values.include?(action)
    GlobalInstrumenter.instrument("suggested_username.publish", {
      suggestion_count: suggestion_count,
      action: action,
      actor: {
        user_id: user_id,
        login: login,
      },
    })
  end

  private

  def descriptor_usernames(base_username:)
    generate_username_suggestions(
      min: DESCRIPTORS_MIN,
      max: MAX_SUGGESTED_USERNAME_ATTEMPTS,
      success_action: EVENT_ACTIONS[:descriptor_generation_success],
      failed_action: EVENT_ACTIONS[:descriptor_generation_failed],
    ) do
      "#{base_username}-#{DESCRIPTORS.sample}"
    end
  end

  def random_number_usernames(base_username:)
    generate_username_suggestions(
      min: RANDOM_NUMBER_MIN,
      max: MAX_SUGGESTED_USERNAME_ATTEMPTS,
      success_action: EVENT_ACTIONS[:random_number_generation_success],
      failed_action: EVENT_ACTIONS[:random_number_generation_failed],
    ) do
      "#{base_username}#{rand(RANDOM_MAX)}"
    end
  end

  # Private:
  # Attempt to generate suggestions up to max suggestions
  # min: Int of the minimum amount of suggestions to determine success or failed
  # max: Int of the maximum amount of suggestions for this type
  # success_action: String for the Hydro event action field when enough usernames are generated
  # failed_action: String for the Hydro event action field when not enough usernames are generated
  # block - block of how you want to generate the usernames
  #
  # Publishes events to hydro for success or failed
  # Returns an array of suggested usernames or an empty array
  def generate_username_suggestions(min:, max:, success_action:, failed_action:, &block)
    suggestions = []
    max.times { suggestions << block.call }
    suggestions.uniq!
    suggestions.map(&:downcase)
    invalid_usernames = User.where(login: suggestions).pluck(:login).map(&:downcase)

    valid_suggestions = suggestions - invalid_usernames

    event_action = valid_suggestions.count >= min ? success_action : failed_action
    publish_suggested_username_event(suggestion_count: valid_suggestions.count, action: event_action)

    valid_suggestions
  end
end
