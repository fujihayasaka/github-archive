# typed: true
# frozen_string_literal: true

class Page::Deployment < ApplicationRecord::Domain::PagesFromRepositories
  include GitHub::Relay::GlobalIdentification


  def self.generate_token
    SecureRandom.hex(5)
  end

  # rubocop:todo Rails/InverseOf
  has_many :builds, -> { order("updated_at desc") }, dependent: :delete_all, foreign_key: "page_deployment_id"
  # rubocop:enable Rails/InverseOf

  include Instrumentation::Model

  before_validation :set_token
  validates_presence_of :page_id, :ref_name, :token
  belongs_to :page
  delegate :repository, to: :page
  after_destroy :destroy_dependent_pages_replicas

  attribute :ref_name, StringFromBinary.new

  def async_repository
    return @async_repository if defined?(@async_repository)

    @async_repository = async_page.then do |page|
      next unless page
      page.async_repository
    end
  end

  # we might consider making this list into a formal state machine
  def pages_deployment_status_list
    base_status = %w[deployment_queued
      deployment_in_progress
      synching_files
      finished_file_synch
      updating_pages
      purging_cdn
      deployment_complete]
    failure_status = base_status.map { |e| e + "_failed" if e != "deployment_complete" }

    base_status + failure_status
  end

  def async_source_directory
    async_page.then do |page|
      next unless page
      page.source_dir
    end
  end

  def async_primary_deployment?
    async_page.then do |page|
      next unless page
      if page.workflow_build_enabled?
        ref_name.eql?(T.must(page.repository).default_branch)
      else
        page.async_source_branch.then do |source_branch|
          ref_name.eql?(source_branch)
        end
      end
    end
  end

  # Is this a deployment for a branch build?
  # Returns true if not the main Pages site.
  def branch_build?
    !async_primary_deployment?.sync
  end

  def set_token
    return if self.token.present?
    self.token = self.class.generate_token
  end

  def unpublish
    self.class.transaction do
      raise ActiveRecord::Rollback unless update(revision: nil)
      destroy_dependent_pages_replicas
    end
  end

  # Destroy all pages_replicas records which belong to this page deployment.
  # Should be run after this Page::Deployment record is destroyed.
  #
  # Returns nothing.
  def destroy_dependent_pages_replicas
    self.class.connection.delete(Arel.sql(<<-SQL, deployment_id: self.id))
      DELETE FROM pages_replicas WHERE pages_deployment_id = :deployment_id
    SQL
  end

  def url
    async_url.sync
  end

  def async_url
    async_primary_deployment?.then do |is_primary_deployment|
      next async_preview_url if !is_primary_deployment
      async_repository.then do |repository|
        next unless repository
        repository.async_gh_pages_url
      end
    end
  end

  def preview_url
    async_preview_url.sync
  end

  def async_preview_url
    async_page.then do |page|
      next unless page
      page.async_repository.then do |repository|
        next unless repository
        Promise.all([repository.async_owner, page.async_primary?]).then do |owner, is_primary|
          next unless owner

          Addressable::URI.new(
            scheme: page.url.scheme,
            host: "#{owner}-#{token}.#{GitHub.pages_preview_hostname}",
            path: is_primary ? "/" : "/#{repository.name}/",
          ).normalize.to_s
        end
      end
    end
  end

  def build_type
    async_build_type.sync
  end

  def async_build_type
    async_page.then { |page| T.must(page).build_type }
  end

  def platform_type_name
    "PageDeployment"
  end
end
