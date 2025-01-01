# typed: true
# frozen_string_literal: true

module SearchDisplayable
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::UTF8

  requires_ancestor { ActiveRecord::Base }

  NAME_BYTESIZE_LIMIT = 1024

  COLORS = {
    gray: 0,
    blue: 1,
    green: 2,
    orange: 3,
    red: 4,
    pink: 5,
    purple: 6,
  }.freeze

  ICONS = {
    zap: 0,
    issue_opened: 1,
    git_pull_request: 2,
    comment_discussion: 3,
    organization: 4,
    people: 5,
    briefcase: 6,
    file_diff: 7,
    code_review: 8,
    codescan: 9,
    terminal: 10,
    tools: 11,
    beaker: 12,
    alert: 13,
    eye: 14,
    telescope: 15,
    bookmark: 16,
    calendar: 17,
    meter: 18,
    moon: 19,
    sun: 20,
    flame: 21,
    bug: 22,
    north_star: 23,
    rocket: 24,
    squirrel: 25,
    hubot: 26,
    dependabot: 27,
    clock: 28,
    smiley: 29,
    mention: 30,
    person: 31,
  }.freeze

  def description
    utf8(read_attribute(:description)) || ""
  end

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))
    # enums
    enum :color, COLORS, suffix: true
    enum :icon, ICONS, suffix: true

    # validations
    validates :name, bytesize: { maximum: NAME_BYTESIZE_LIMIT }, presence: true,
    unicode: true

    validates :icon, :color, presence: true

    validates :description, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true

    # attributes
    attribute :description, StringFromBinary.new
  end
end
