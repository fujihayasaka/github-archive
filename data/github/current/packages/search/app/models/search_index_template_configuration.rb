# typed: true
# frozen_string_literal: true

class SearchIndexTemplateConfiguration < ApplicationRecord::Mysql5
  include GitHub::Validations
  alias_attribute :writable, :is_writable
  alias_attribute :primary,  :is_primary
  alias_attribute :name,     :template_type
  alias_attribute :version,  :template_version

  validates_presence_of :fullname, :cluster, :template_type, :template_version, :version_sha
  validates :version_sha, length: { is: 40 }, allow_nil: true
  validate :fullname_is_in_sync
  validates :fullname, unicode3: true

  before_validation :update_defaults_and_propagate_changes

  before_create  :create_template
  before_destroy :delete_template

  def update_defaults_and_propagate_changes
    self.version_sha ||= current_version_sha

    local_slicer = slicer
    if fullname_changed?
      self.template_type    = local_slicer.index
      self.template_version = local_slicer.index_version.to_i
    elsif fullname == fullname_adjusted
      local_slicer.index         = template_type    if template_type_changed?
      local_slicer.index_version = template_version if template_version_changed?
      self.fullname = local_slicer.fullname         if template_type_changed? || template_version_changed?
    end
  end

  def fullname_is_in_sync
    slicer = index_class.slicer
    slicer.index = template_type
    slicer.index_version = template_version == 0 ? nil : template_version

    if fullname_adjusted != slicer.fullname
      errors.add(:fullname, "not in sync with the `name` and `version`")
    end
  end

  # Create the index template on the search cluster if it does not already
  # exist.
  #
  # Returns the response from the Elasticsearch cluster
  def create_template
    return if exists?

    Elastomer::SearchIndexManager.create_template \
        name:        fullname,
        cluster:     cluster,
        primary:     is_primary,
        index_class: index_class

    self.version_sha = current_version_sha

  rescue ElastomerClient::Client::Error => err
    Failbot.report(err)
    errors.add(:base, "could not create the index template: <#{err.class.name}> #{err.message}")
    false
  end

  # Deletes the index template from the Elasticsearch cluster.
  #
  # force - Boolean used to force deletion of the template even if it is the
  #         primary template
  #
  # Returns the response from the Elasticsearch cluster
  def delete_template(force: false)
    if primary? && !force
      errors.add(:base, "cannot delete the primary index template")
      return false
    end
    return unless exists?

    Elastomer::SearchIndexManager.delete_template \
        name:        fullname,
        cluster:     cluster,
        force:       force,
        index_class: index_class

  rescue ElastomerClient::Client::Error => err
    Failbot.report(err)
    errors.add(:base, "could not delete the index template: <#{err.class.name}> #{err.message}")
    false
  end

  # Add the primary alias to the index template. This method is a noop
  # if the index template is already the primary or if the index template
  # does not exist.
  #
  # Returns nil (on noop) or the response from the Elasticsearch cluster.
  def add_primary
    return if primary? || !exists?

    hash = get_template
    hash["aliases"] = { primary_alias => {} }
    template.create(hash)

    update_attribute(:is_primary, true)
  end

  # Remove the primary alias from the index template. This method is a noop
  # if the index template is not already the primary or if the index
  # template does not exist.
  #
  # Returns nil (on noop) or the response from the Elasticsearch cluster.
  def remove_primary
    return if !primary? || !exists?

    hash = get_template
    hash["aliases"] = {}
    template.create(hash)

    update_attribute(:is_primary, false)
  end

  # Computes the current version SHA for the underlying `Elastomer::Index`
  # class based on the mappings and settings found in the index classs itself.
  # This version SHA is stored in the database, and it is used to determine if
  # the index tempalte on the search cluster is in sync with the data found here
  # in the source code.
  #
  # Returns a 40 character SHA1 String
  def current_version_sha
    @current_version_sha ||= Elastomer::SearchIndexManager.version \
        mappings:   index_class.mappings(cluster),
        settings:   index_class.settings(cluster)
  end

  # Returns true if the index template exists on the search cluster.
  def exists?
    response = client.head "/_template/#{fullname}"
    response.success?
  end
  alias :exist? :exists?

  # Returns true if this index template is up to date with the mappings and
  # settings defined in the Index class.
  def current?
    exists? && version_sha == current_version_sha
  end

  # Internal: Our original audit log search index template appeneded a
  # "_template" to the end of the template name. We have moved away from that
  # convention, but still need to handle it gracefully. This accessor prunes
  # that trailing "_template" string from the fullname.
  def fullname_adjusted
    fullname.sub(/_template\z/, "")
  end

  # Internal: Returns a Slicer instance configured with the the name of this
  # index template.
  def slicer
    slicer = index_class.slicer
    slicer.fullname = fullname_adjusted
    slicer
  end

  # Internal: Returns the Elastomer index class for this template config.
  def index_class
    @index_class ||= begin
      index_name = fullname_adjusted
      Elastomer.env.lookup_index(index_name)
    end
  end

  # Internal: Returns the ElastomerClient::Client connected to the desired search
  # cluster.
  def client
    Elastomer.router.client(cluster)
  end

  # Internal: Returns the ElastomerClient::Client::Template instance configured
  # with the index tmplate `fullname`.
  def template
    client.template(fullname)
  end

  # Internal: Returns the primary alias name for the index class associated
  # with this index template.
  def primary_alias
    slicer.index_alias
  end

  # Internal: Get the template from the Elasticsearch cluster.
  #
  # Returns the template Hash or nil
  def get_template
    hash = template.get
    hash[fullname]
  end
end
