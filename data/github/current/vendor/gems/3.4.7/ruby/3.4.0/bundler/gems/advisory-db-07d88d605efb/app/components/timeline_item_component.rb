# frozen_string_literal: true

class TimelineItemComponent < ApplicationComponent
  class << self
    def for_version(version, subject: nil)
      event_name = version.event_name
      return unless event_name

      subclass =
        begin
          const_get(event_name.to_s.classify)
        rescue NameError
          Unknown
        end

      subclass.new(
        version: version,
        event_name: event_name,
        subject: subject,
      )
    end

    attr_reader :badge_icon, :badge_bg, :active_verb, :passive_verb

    def badge(icon:, bg: nil)
      @badge_icon = icon
      @badge_bg = bg
    end

    def verb(verb = nil, active: verb, passive: verb)
      @active_verb = active
      @passive_verb = passive
    end

    def show_data
      @show_data = true
    end

    def show_diff
      @show_diff = true
    end

    def show_data?
      @show_data == true
    end

    def show_diff?
      @show_diff == true
    end
  end

  attr_reader :version, :event_name, :subject

  def initialize(version:, event_name:, subject: nil)
    @version = version
    @event_name = event_name
    @subject = subject
  end

  def render?
    version.present? && object.present?
  end

  def primary?
    object == subject
  end

  def object
    version.item
  end

  def badge_icon
    self.class.badge_icon
  end

  def badge_bg
    primary? ? self.class.badge_bg : nil
  end

  def badge_color
    badge_bg ? :on_emphasis : nil
  end

  def actor
    version.user
  end

  def actor_avatar(**args)
    return unless actor

    Primer::Beta::Avatar.new(src: actor.avatar_url, alt: actor.login, **args)
  end

  def noun
    object.class.name.underscore.humanize
  end

  def identifier
    object.to_param
  end

  def identified_noun(capitalize: false)
    capture do
      if primary?
        concat "this ".humanize(capitalize: capitalize)
        concat noun.humanize(capitalize: false) if noun
      else
        capture do
          concat noun.humanize(capitalize: capitalize) if noun

          if identifier
            concat " "
            concat tag.code(identifier, class: "bg-gray p-1 rounded-1")
          end
        end
      end
    end
  end

  def active_verb
    self.class.active_verb
  end

  def passive_verb
    self.class.passive_verb
  end

  def timestamp
    version.created_at
  end

  def show_data?
    self.class.show_data?
  end

  def show_diff?
    self.class.show_diff?
  end

  def diff
    version.diff.to_s.html_safe # rubocop:disable Rails/OutputSafety
  end

  def toggle_id
    @toggle_id ||= "toggle-#{id}"
  end

  def id
    @id ||= "#{event_name}_#{version.id}".dasherize
  end

  def test_selector
    "timeline_item_#{event_name}".dasherize
  end

  # Override phrasing template in timeline_item_component.
  def phrase_override
    nil
  end

  # SUBCLASSES

  class AdvisoryAutoPublish < self
    badge icon: "check-circle", bg: :done_emphasis
    verb "auto-published"
    show_data
  end

  class AdvisoryPublish < self
    badge icon: "check-circle", bg: :done_emphasis
    verb "published"
    show_data
  end

  class AdvisoryUpdate < self
    badge icon: "pencil", bg: :accent_emphasis
    verb "updated"
    show_diff
  end

  class AdvisoryWithdraw < self
    badge icon: "no-entry", bg: :danger_emphasis
    verb active: "withdrew", passive: "withdrawn"
  end

  class AdvisoryAlertingEventStartProcessing < self
    badge icon: "sync", bg: :open_emphasis
    verb active: "started processing", passive: "processed"

    def phrase_override
      "Started processing alerts"
    end
  end

  class AdvisoryAlertingEventProcessed < self
    badge icon: "paper-airplane", bg: :success_emphasis
    verb active: "processing", passive: "processed"
    def phrase_override
      "Finished processing alerts"
    end
  end

  class AdvisoryAlertingEventFinished < self
    badge icon: "bell", bg: :done_emphasis
    verb active: "sending alerts", passive: "sent alerts"

    def phrase_override
      "Sent alerts"
    end
  end

  class AdvisoryReviewClose < self
    badge icon: "x-circle", bg: :danger_emphasis
    verb "closed"
  end

  class AdvisoryReviewOpen < self
    badge icon: "issue-opened", bg: :success_emphasis
    verb "opened"
    show_data
  end

  class AdvisoryReviewApprove < self
    badge icon: "check-circle", bg: :success_emphasis
    verb "approved"

    def primary?
      true
    end

    def noun
      "advisory review"
    end
  end

  class AdvisoryReviewAssign < self
    badge icon: "person", bg: :success_emphasis
    verb "assigned"

    def primary?
      true
    end

    def noun
      user_id = version.changeset["user_id"][1]
      "advisory review to #{User.find(user_id).login}"
    end
  end

  class AdvisoryReviewPublish < self
    badge icon: "check-circle", bg: :done_emphasis
    verb "published"
  end

  class AdvisoryReviewReopen < self
    badge icon: "issue-opened", bg: :success_emphasis
    verb "reopened"
  end

  class AdvisoryReviewRevert < self
    badge icon: "reply", bg: :danger_emphasis
    verb "reverted"
    show_diff
  end

  class AdvisoryReviewUpdate < self
    badge icon: "pencil", bg: :accent_emphasis
    verb "updated"
    show_diff
  end

  class AdvisoryReviewWithdraw < self
    badge icon: "no-entry", bg: :done_emphasis
    verb active: "withdrew", passive: "withdrawn"
  end

  class CVEPublish < self
    badge icon: "check-circle", bg: :done_emphasis
    verb "published"
    show_data
  end

  class CVERequest < self
    badge icon: "diff-added", bg: :success_emphasis
    verb "requested"
    show_data
  end

  class CVEReviewAssign < self
    badge icon: "shield-lock", bg: :done_emphasis
    verb "assigned"
    show_data
  end

  class CVEReviewClose < self
    badge icon: "x-circle", bg: :danger_emphasis
    verb "closed"
    show_data
  end

  class CVEReviewOpen < self
    badge icon: "issue-opened", bg: :success_emphasis
    verb "opened"
    show_data
  end

  class CVEReviewPublish < self
    badge icon: "check-circle", bg: :done_emphasis
    verb "published"
  end

  class CVEReviewReject < self
    badge icon: "no-entry", bg: :danger_emphasis
    verb "rejected"
  end

  class CVEReviewReopen < self
    badge icon: "issue-opened", bg: :success_emphasis
    verb "reopened"
  end

  class CVEReviewUpdate < self
    badge icon: "pencil", bg: :accent_emphasis
    verb "updated"
    show_diff
  end

  class FeedEntryImport < self
    badge icon: "diff-added", bg: :success_emphasis
    verb "imported"
    show_data
  end

  class FeedEntryUpdate < self
    badge icon: "diff-modified", bg: :accent_emphasis
    verb "updated"
    show_diff
  end

  class VulnerabilityPublish < self
    badge icon: "check-circle", bg: :success_emphasis
    verb "published"
    show_data
  end

  class VulnerabilityUpdate < self
    badge icon: "pencil", bg: :accent_emphasis
    verb "updated"
    show_diff
  end

  class VulnerabilityWithdraw < self
    badge icon: "no-entry", bg: :done_emphasis
    verb active: "withdrew", passive: "withdrawn"
  end

  # The Unknown class is a fall-back for unknown events.
  class Unknown < self
    badge icon: "question"
    verb "changed"
  end
end
