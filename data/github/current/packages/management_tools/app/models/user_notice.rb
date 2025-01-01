# typed: true
# frozen_string_literal: true

class UserNotice
  attr_reader :name, :effective_date, :hide_from_new_user, :decommission_date

  DEFAULT_NOTICES_PATH = Rails.root.join("config", "notices.yml")

  alias hide_from_new_user? hide_from_new_user

  def initialize(options)
    @options            = options
    @name               = options.fetch("name")
    @decommission_date  = options.fetch("decommission_date", nil)
    unless decommissioned?
      @effective_date     = options.fetch("effective_date")
      @hide_from_new_user = options.fetch("hide_from_new_user")
    end
  end

  def self.all
    load_notices unless @all
    @all
  end

  def self.find(name)
    self.all.detect { |notice| notice.name.to_s.downcase == name.to_s.downcase }
  end

  def self.load_notices(file_path = DEFAULT_NOTICES_PATH)
    notice_definitions = YAML.safe_load(File.read(file_path))["notices"]

    @all = notice_definitions.map do |info|
      notice = new(info)
      set_constant(notice)
      notice
    end.compact
  end

  def decommissioned?
    return false if decommission_date.blank?

    DateTime.parse(decommission_date) < DateTime.now
  end

  def effective_at
    return if effective_date.blank?
    DateTime.parse(effective_date)
  end

  def effective?
    return false if decommissioned?
    return false if effective_date.blank?

    effective_at <= DateTime.now
  end

  def constant_name
    name.end_with?("_notice") ? name.upcase : "#{name}_notice".upcase
  end

  def self.set_constant(notice)
    UserNotice.const_set(notice.constant_name, notice.name) unless UserNotice.const_defined?(notice.constant_name.to_sym)
  end
  private_class_method :set_constant

  load_notices
end
