# typed: true
# frozen_string_literal: true

class PreReceiveHook < ApplicationRecord::Domain::PreReceive
  include Instrumentation::Model
  include GitHub::Validations

  belongs_to :environment, class_name: "PreReceiveEnvironment"
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true
  # rubocop:todo Rails/InverseOf
  has_many :targets, class_name: "PreReceiveHookTarget", foreign_key: "hook_id", dependent: :destroy
  # rubocop:enable Rails/InverseOf
  validates_presence_of :environment
  validates_presence_of :repository
  validates_presence_of :script
  validates_presence_of :name
  validates_uniqueness_of :name, case_sensitive: false
  validates_uniqueness_of :script, scope: :repository_id, case_sensitive: false

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy

  after_commit :synchronize_git_checkout

  def instrument_create
    instrument :create
  end

  def instrument_update
    instrument :update
  end

  def instrument_destroy
    instrument :destroy
  end

  def synchronize_git_checkout
    if self.destroyed?
      # TODO: implement cleanup if no hooks with the same repo exist anymore
    elsif previous_changes.key?("repository_id")
      PreReceiveRepositoryUpdateJob.perform_later(T.must(repository).id, repository_url)
    end
  end

  def repository_url
    shard_path = T.must(repository).shard_path
    if Rails.env.production?
      "git://#{T.must(repository).host}:#{GitHub.git_daemon_port}#{shard_path.sub(GitHub.repository_root, "")}"
    else
      "file://#{shard_path}"
    end
  end

  def event_prefix
    :pre_receive_hook
  end

  def event_payload
    { event_prefix => self, :public_repo => repository&.public?, }
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def self.sorted_by(order = nil, direction = nil)
    direction = "DESC" == "#{direction}".upcase ? "DESC" : "ASC"
    order = "id" unless order == "name"
    order([order, direction].join(" "))
  end
end
