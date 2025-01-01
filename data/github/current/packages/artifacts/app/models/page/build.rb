# typed: false
# frozen_string_literal: true

class Page::Build < ApplicationRecord::Pages
  include Instrumentation::Model
  include Coders::CodableColumn

  STATUS_BUILDING = "building".freeze
  STATUS_ERRORED  = "errored".freeze
  STATUS_BUILT    = "built".freeze
  STATUSES = Set.new([STATUS_BUILDING, STATUS_ERRORED, STATUS_BUILT]).freeze

  attr_accessor :previous_status
  belongs_to :page
  validates_presence_of :page_id, :pusher_id, :status
  validates_inclusion_of :status, in: STATUSES
  delegate :repository, to: :page

  # To aid in transitioning from raw_data to proper MySQL columns, read and
  # write from both places.
  serialize_with_coder :raw_data, Coders::Page::BuildCoder, :multi_read_writer

  def multi_read_writer
    @multi_read_writer ||= Coders::MultiReadWriter.new(
      sources:    [self, raw_data],
      attributes: Coders::Page::BuildCoder.reader_members,
    )
  end

  # Public: Creates a new Page::Build to track a build.
  #
  # page  - A Page instance.
  # attrs - Hash of attributes.
  #         :commit - String SHA of the commit that is being built.
  #         :pusher - User that initiated the page build.
  #
  # Returns a saved Page::Build.
  def self.track(page, attrs = {})
    build = new({
      page: page,
      commit: attrs[:commit],
      status: STATUS_BUILDING,
      page_deployment_id: attrs[:page_deployment_id],
    })
    build.pusher_id = attrs[:pusher].id
    build.save!
    build
  end

  # Marks the Page::Build in an error state.
  #
  # duration - An Integer of how long the build took, in seconds.
  #
  # Returns nothing.
  def error!(exception, duration = nil)
    max_duration = 1.day.to_i * 1_000
    self.duration = duration.to_i >= max_duration ? max_duration : duration.to_i
    self.error = exception.to_s
    self.backtrace = exception.backtrace[0..99].join("\n") unless exception.backtrace.nil?
    self.previous_status = status
    self.status = STATUS_ERRORED
    save!
    update_page_status
    instrument_finished

    PagesMailer.build_failure(pusher, repository, exception.message, self).deliver_later if pusher
    if [GitHub::Pages::Builder::UserError, Page::InvalidCNAME].include? exception.class
      GitHub.dogstats.increment("pages.builds", tags: ["status:failure"])
    else
      GitHub.dogstats.increment("pages.builds", tags: ["status:error"])
    end
  end

  # Did this build fail?
  #
  # Returns a boolean.
  def errored?
    status == STATUS_ERRORED
  end
  alias_method :error?, :errored?

  # Is this build still building?
  #
  # Returns a boolean.
  def building?
    status == STATUS_BUILDING
  end

  # Did this build build?
  #
  # Returns a boolean
  def built?
    status == STATUS_BUILT
  end

  # Marks the Page::Build as complete.
  #
  # duration - An Integer of how long the build took, in seconds.
  #
  # Returns nothing.
  def complete!(duration = nil)
    max_duration = 1.day.to_i * 1_000
    self.duration = duration.to_i >= max_duration ? max_duration : duration.to_i
    self.error = self.backtrace = nil
    self.previous_status = status
    self.status = STATUS_BUILT
    save!
    instrument_finished
    update_page_status
    GitHub.dogstats.increment("pages.builds", tags: ["status:success"])
  end

  def pusher=(user)
    user_id = user.try(:id).to_i
    if user_id == 0
      @pusher = self.pusher_id = nil
    else
      self.pusher_id = user_id
      @pusher = user
    end
  end

  # Pusher is nil if pushed from a deploy key.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def pusher
    @pusher ||= begin
      id = pusher_id.to_i
      id > 0 && User.find_by_id(id)
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def update_page_status
    return if deployment&.branch_build?
    Page.where(id: page_id).update_all(status: status)
  end
  after_create :update_page_status

  def status_changed?
    previous_status != status
  end

  def event_context(prefix: :page_build)
    {
      "#{prefix}_id".to_sym => id,
    }
  end

  def deployment
    return nil unless page_deployment_id.present?
    Page::Deployment.where(id: page_deployment_id).first
  end

  def duration_in_seconds
    duration.to_f / 1_000
  end

  private

  def event_payload
    {
      page_build:      self,
      status:          status,
      previous_status: previous_status,
      page:            page,
      public_repo:     page.repository.public?
    }
  end

  def instrument_finished
    instrument :finished
  end
end
