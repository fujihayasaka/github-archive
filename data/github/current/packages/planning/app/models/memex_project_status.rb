# typed: true
# frozen_string_literal: true

class MemexProjectStatus < ApplicationRecord::Domain::Memexes

  include GitHub::Validations
  include Instrumentation::Model
  include UserContentEditable
  include GitHub::UserContent
  include Spam::Spammable
  include Notifications::SubscribableThread

  STATUS_OPTIONS = {
    "8be313fb" => {
      id: "8be313fb",
      name: "Inactive",
      nameHtml: "Inactive",
      color: "GRAY",
      description: "This project is inactive."
    },
    "459eafad" => {
      id: "459eafad",
      name: "On track",
      nameHtml: "On track",
      color: "GREEN",
      description: "This project is on track with no risks."
    },
    "366655d6" => {
      id: "366655d6",
      name: "At risk",
      nameHtml: "At risk",
      color: "YELLOW",
      description: "This project is at risk and encountering some challenges."
    },
    "04201a9a" => {
      id: "04201a9a",
      name: "Off track",
      nameHtml: "Off track",
      color: "RED",
      description: "This project is off track and needs attention."
    },
    "c77b75a3" => {
      id: "c77b75a3",
      name: "Complete",
      nameHtml: "Complete",
      color: "PURPLE",
      description: "This project is complete."
    },
  }.freeze

  belongs_to :memex_project, inverse_of: :memex_project_statuses
  belongs_to :creator, class_name: "User"

  setup_spammable :creator

  validates :creator, presence: true
  validates :memex_project, presence: true
  validates :status_id, inclusion: { in: STATUS_OPTIONS.keys }, allow_nil: true
  validate :validate_options_in_status_value
  validate :status_value_or_body_present
  validate :require_non_template

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update

  before_destroy :generate_delete_webhook_payload
  after_commit :queue_delete_webhook_delivery, on: :destroy

  def formatter
    :markdown
  end

  sig { params(memex_project: MemexProject, creator: User, create_params: T.any(T::Hash[Symbol, T.untyped], ActionController::Parameters)).returns(MemexProjectStatus) }
  def self.build_for_project(memex_project, creator, create_params)
    new_update = build({
      creator: creator,
      memex_project: memex_project,
      body: create_params[:body],
      status_id: create_params[:status_id],
      start_date: create_params[:start_date],
      target_date: create_params[:target_date],
    })

    status_value = {
      # we only save the status_id, but return the entire option in to_hash
      status_id: create_params[:status_id],
      start_date: create_params[:start_date],
      target_date: create_params[:target_date],
    }

    new_update.status_value = status_value.to_json

    new_update
  end

  def to_hash(viewer, cap_filter)
    status_hash = JSON.parse(status_value)
    status_hash["status"] = STATUS_OPTIONS[status_hash["status_id"]]

    {
      id: id,
      creator: creator_hash,
      body: body,
      body_html: body_html(context: pipeline_context(viewer, cap_filter)),
      status_value: status_hash,
      updated_at: updated_at,
      user_hidden: user_hidden
    }
  end

  sig { returns(T.nilable(String)) }
  def status_name_html
    status_id = parse_status_value[:status_id]
    option = STATUS_OPTIONS[status_id]

    option&.dig(:nameHtml)
  end

  def self.status_options
    STATUS_OPTIONS.values
  end

  sig { params(name: String).returns(String) }
  def self.status_name_to_enum(name)
    name.parameterize(separator: "_").upcase
  end

  # Convert a status id to the corresponding ProjectV2StatusUpdateStatus value
  sig { params(status_id: T.nilable(String)).returns(T.nilable(String)) }
  def self.status_id_to_enum_string(status_id)
    name = STATUS_OPTIONS.dig(status_id, :name)
    self.status_name_to_enum(name) if name
  end

  # Convert a ProjectV2StatusUpdateStatus value into the corresponding status id
  sig { params(status_enum: String).returns(T.nilable(String)) }
  def self.status_enum_string_to_id(status_enum)
    match = STATUS_OPTIONS.values.find { |opt| status_name_to_enum(opt[:name]) == status_enum }
    match&.dig(:id)
  end

  sig { params(include_host: T::Boolean).returns(T.nilable(String)) }
  def permalink(include_host: true)
    return unless persisted? && (project = memex_project)

    if include_host
      "#{GitHub.url}#{project.url}?pane=info&statusUpdateId=#{id}"
    else
      "#{project.url}?pane=info&statusUpdateId=#{id}"
    end
  end

  # GitHub::UserContent expects the async_user method to exist and return the author necessary for performing
  # permission checks for mentioned teams.
  #
  # When a MemexProjectStatus is updated the GitHub::UserContent module obtains the user from the UserContentEditable
  # interface.
  sig { returns(Promise[T.nilable(User)]) }
  def async_user
    async_creator
  end

  sig { returns(T.nilable(User)) }
  def user
    creator
  end

  # GitHub::UserContext expects the async_organization method to lookup mentioned teams.
  sig { returns(Promise[T.nilable(Organization)]) }
  def async_organization
    async_memex_project.then do |memex_project|
      T.must(memex_project).async_owner.then do |owner|
        if owner.is_a?(::Organization)
          owner
        else
          Promise.resolve(nil)
        end
      end
    end
  end

  sig { returns(T.nilable(::Organization)) }
  def organization
    async_organization.sync
  end

  # Fallback on the ghost user when the original author's been deleted.
  # See User.ghost for more.
  sig { returns(User) }
  def safe_creator
    creator || User.ghost
  end

  # The user who performed the action as set in the GitHub request context. If the context doesn't
  # contain an actor, fallback to the safe_user which we know exists.
  sig { returns(User) }
  def modifying_user
    if (actor_id = GitHub.context[:actor_id]).present?
      User.find_by(id: actor_id) || safe_creator
    else
      safe_creator
    end
  end
  attr_writer :modifying_user

  # The unique Message-ID header value for notifications and email.
  sig { returns(T.nilable(String)) }
  def message_id
    return unless persisted? && (project = memex_project) && (owner = project.owner)

    "<#{owner.display_login}/projects/#{project.id}/statuses/#{id}@#{GitHub.urls.host_name}>"
  end

  sig { returns(Promise[T.nilable(T.any(User, Organization))]) }
  def async_notifications_list
    async_memex_project.then do |memex_project|
      T.must(memex_project).async_owner
    end
  end

  sig { returns(T.nilable(MemexProject)) }
  def notifications_thread
    memex_project
  end

  sig { returns(T.nilable(User)) }
  def notifications_author
    creator
  end

  def self.latest_project_status_update
    latest_status_updates_ids = select("max(id)").group(:memex_project_id)
    where(id: latest_status_updates_ids)
  end

  sig { params(actor: T.nilable(User)).returns(String) }
  def email_body(actor = nil)
    body_html(context: pipeline_context.merge({ for_email: true, viewer: actor }))
  end

  sig { returns(String) }
  def platform_type_name
    "ProjectV2StatusUpdate"
  end

  private

  def validate_options_in_status_value
    return unless status_value.present?

    status_hash = JSON.parse(status_value)
    valid_options = %w[status_id start_date target_date]

    unless (status_hash.keys - valid_options).empty?
      errors.add(:base, "invalid extra input was provided")
      return
    end

    if FeatureFlag.vexi.enabled?(:memex_status_update_date_validation, modifying_user, default: false)
      unless valid_date?(status_hash["start_date"])
        errors.add(:start_date, "not a recognized date format")
      end

      unless valid_date?(status_hash["target_date"])
        errors.add(:target_date, "not a recognized date format")
      end
    else
      begin
        Date.parse(status_hash["start_date"])
      rescue ArgumentError
        errors.add(:start_date, "not a recognized date format")
      end if status_hash["start_date"]&.present?

      begin
        Date.parse(status_hash["target_date"])
      rescue ArgumentError
        errors.add(:target_date, "not a recognized date format")
      end if status_hash["target_date"]&.present?
    end

    if status_hash["status_id"]
      status_option = STATUS_OPTIONS[status_hash["status_id"]]
      errors.add(:base, "status is invalid") unless status_option.present?
    end

  end

  def status_value_or_body_present
    status_hash = status_value ? JSON.parse(status_value) : {}
    return if body.present? || status_hash["status_id"].present? || status_hash["start_date"].present? || status_hash["target_date"].present?
    errors.add(:base, "status, start date, target date or body must be present")
  end

  sig { params(date_string: T.nilable(String)).returns(T::Boolean) }
  def valid_date?(date_string)
    return true if date_string.nil? || date_string.empty? # nil or "" are both valid ways to clear the date value
    return false if date_string.blank? # a non-empty pure whitespace string is considered invalid

    begin
      iso = DateTime.iso8601(date_string.strip)
      MemexDateTimeFormat.parse(iso.to_s)
      true
    rescue MemexDateTimeFormat::FormatError, ArgumentError
      false
    end
  end

  def creator_hash
    return unless (creator = self.creator)

    {
      id: creator.id,
      login: creator.display_login,
      name: creator.name,
      avatarUrl: creator.primary_avatar_url(40)
    }
  end

  def pipeline_context(viewer = nil, cap_filter = nil)
    {
      viewer: viewer,
      memex_project: memex_project,
      unfurl_references: true,
      cap_filter: cap_filter
    }
  end

  # Emits an event to the GlobalInstrumenter that a new MemexProjectStatus was created
  # This will be used for notifications & and potentially hydro messages in the future
  def notify_on_create
    if memex_status_updates_notifications_enabled?
      GlobalInstrumenter.instrument("memex_project_status.create", {
        actor: creator,
        memex_project_status: self,
      })
    end
  end

  # Emits an event to the GlobalInstrumenter that a new MemexProjectStatus was updated
  # This will be used for notifications & and potentially hydro messages in the future
  def notify_on_update
    if memex_status_updates_notifications_enabled?
      previous_body, current_body = body_changes

      GlobalInstrumenter.instrument("memex_project_status.update", {
        actor: modifying_user,
        memex_project_status: self,
        previous_body: previous_body,
        current_body: current_body,
      })
    end
  end

  def event_payload
    {
      memex_project_status_id: id,
      org_id: memex_project&.organization_owner_id,
      changes: previous_changes
    }.compact
  end

  sig { void }
  def instrument_create
    if memex_project&.org_owned?
      payload_actor = creator || User.ghost

      instrument(:create, actor_id: payload_actor&.id)
    end
    notify_on_create
  end

  sig { void }
  def instrument_update
    if memex_project&.org_owned?
      instrument(:update, actor_id: modifying_user.id)
    end
    notify_on_update
  end

  sig { void }
  def generate_delete_webhook_payload
    # This guard is necessary because deliverable? is checked when using .new => .deliver_later
    return if !memex_project&.organization_owner_id

    event = Hook::Event::ProjectsV2StatusUpdateEvent.new(
      action: :deleted,
      memex_project_status_id: id,
      actor_id: modifying_user.id,
      org_id: memex_project&.organization_owner_id
    )

    @future_webhook_delivery = Hook::DeliverySystem.new(event)
    @future_webhook_delivery.generate_hookshot_payloads
  end

  sig { void }
  def queue_delete_webhook_delivery
    return unless defined?(@future_webhook_delivery)
    @future_webhook_delivery.deliver_later
    remove_instance_variable(:@future_webhook_delivery)
  end

  # This is defined locally as we don't have access to the current_user/current_org to use the controller based helpers
  sig { returns(T::Boolean) }
  def memex_status_updates_notifications_enabled?
    !!(FeatureFlag.vexi.enabled?(:memex_status_updates_notifications, modifying_user, default: false) ||
      (memex_project&.owner.organization? && FeatureFlag.vexi.enabled?(:memex_status_updates_notifications, memex_project&.owner, default: false)))
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def parse_status_value
    JSON.parse(status_value).deep_symbolize_keys
  end

  sig { void }
  private def require_non_template
    if memex_project&.is_template?
      errors.add(:base, "Cannot perform this action on a template")
    end
  end
end
