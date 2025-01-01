# typed: true
# frozen_string_literal: true

class MemexProjectColumn::Settings::OptionEntry
  include ActiveModel::Validations
  include GitHub::Validations
  include MemexProjectColumn::Groupable::Metadata
  include MemexProjectColumn::Sliceable::Metadata

  attr_reader :id, :name, :name_html, :color, :description, :description_html

  ID_REGEX = /\A[a-f0-9]{8}\z/
  NAME_BYTESIZE_LIMIT = 1024
  DESCRIPTION_CHAR_LIMIT = 450
  DEFAULT_COLOR = MemexProjectColumn::Settings::DEFAULT_COLOR
  ALLOWED_COLORS = MemexProjectColumn::Settings::ALLOWED_COLORS

  validates_format_of :id, with: ID_REGEX, allow_blank: false
  validates :name, presence: true, bytesize: { maximum: NAME_BYTESIZE_LIMIT }, unicode: true
  validates :name_html, presence: true
  validates :color, presence: true, inclusion: { in: ALLOWED_COLORS }
  validates :description, length: { maximum: DESCRIPTION_CHAR_LIMIT }, unicode: true
  validate :validate_description

  # TODO: add this (and change the allow_blanks above) once we can enforce these on write
  # validates :description_html, presence: true

  def self.generate_id
    SecureRandom.hex(4)
  end

  def initialize(args)
    @id = args[:id].presence || self.class.generate_id
    @name = args[:name]&.strip
    @name_html = (args[:name_html] || GitHub::Goomba::MemexTextColumnPipeline.to_html(@name)) if @name
    @color = args[:color].presence || DEFAULT_COLOR
    @description = args[:description]&.strip || ""
    @description_html = (args[:description_html] || GitHub::Goomba::MemexTextColumnPipeline.to_html(@description)) if @description
  end

  def attributes
    return @attributes if defined?(@attributes)

    @attributes = {
      id: @id,
      name: @name,
      name_html: @name_html,
      color: @color,
      description: @description,
      description_html: @description_html,
    }.compact.with_indifferent_access
  end
  alias_method :group_metadata, :attributes
  alias_method :slice_metadata, :attributes

  def name=(name)
    @name = name
    @name_html = GitHub::Goomba::MemexTextColumnPipeline.to_html(name)
  end

  def color=(color)
    # use default if there's no saved color, makes the UI types easier
    if !color.in?(ALLOWED_COLORS)
      color = DEFAULT_COLOR
    end

    @color = color
  end

  def description=(description)
    # use default if there's no saved description, makes the UI types easier
    if description.blank?
      description = ""
    end

    @description = description
    @description_html = GitHub::Goomba::MemexTextColumnPipeline.to_html(description)
  end

  def validate_description
    # allow empty string, but not nil
    if @description.nil?
      errors.add(:description, "can't be nil")
    end
  end

  # The bytesize validation from `GitHub::Validations` requires that we define
  # the set of attributes that have changed on this object.
  def changed
    return @changed if defined?(@changed)

    # Note that this object must have string keys to confirm to Rails conventions.
    @changed = { "name" => @name, "color" => @color, "description" => @description }
  end
end
