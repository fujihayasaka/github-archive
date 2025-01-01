# typed: true
# frozen_string_literal: true

# Models an annotated tag object retrieved or to-be-written-to the underlying
# git repository. Tag objects include attributes that are similar to a Commit
# (#message, #author, #authored_date) but are meant to represent a meaningful
# point in time in history.
#
# This model does not handle lightweight tags or the creation of tag refs. All
# refs under the refs/tags/* namespace should be managed by Git::Ref::Collection.
# Refs may or may not point to a real Tag object.
#
# TODO Creation of new git tag objects.
class Tag
  include GitRPC::Util
  include Commits::CommitMessageable
  include GitSigning::Verifiable
  include GitHub::Relay::GlobalIdentification

  # The Repository object this tag belongs to.
  attr_reader :repository

  # The tag's name as specified on the git tag object. Note that this name does
  # not come from the suffix part of the "refs/tags/*" ref name. It's embedded
  # directly in the tag object itself and may even be different.
  attr_reader :name

  # The oid of the tag object.
  attr_reader :oid

  # The tag object's long message.
  attr_reader :message

  # The target oid. This usually identifies a Commit but may also be a Blob or Tree.
  # See the #target and #commit methods for info on accessing the target object.
  attr_reader :target_oid

  # The target object's type. 'commit', 'tag', 'tree', or 'blob'. This is nil for
  # lightweight tags since the object type is unknown. This value comes from the
  # target type field stored in the git tag object and is therefore available
  # before the target has been loaded.
  attr_reader :target_type

  # Author information. This information is embedded in the git tag object and
  # is not related to the commit target.
  attr_reader :author_name, :author_email, :authored_date_value

  # Read signatures and signing payloads from GitRPC for a group of tags.
  #
  # repo - The Repository all the tags belong to.
  # oids - An Array of String tag OIDs.
  #
  # Returns an Array of Arrays. The first element of each array is the signature
  # and the second element is the signing payload.
  def self.parse_signing_data(repo, oids)
    repo.rpc.parse_tag_signatures(oids)
  end

  # Has the `@author` instance variable already been set?
  #
  # Returns boolean.
  def author_defined?
    defined?(@author)
  end

  # Initialize a new Tag object with information loaded from the git object store.
  #
  # repository - The Repository this tag was loaded from.
  # info       - Tag information hash. See below for details on this structure.
  #
  # The info argument is a hash with the following string keys:
  #   { 'oid'         => string oid (SHA1) of the real tag object,
  #     'name'        => string tag name,
  #     'message'     => string tag message,
  #     'tagger'      => [name, email, time] author array,
  #     'target'      => string destination object oid (SHA1),
  #     'target_type' => string type of the destination object }
  #
  # The info hash data structure is defined by gitrpc:
  #   https://github.com/github/gitrpc/blob/master/doc/read_tags.md
  def initialize(repository, info = {})
    @repository = repository
    @name = info["name"]
    @oid  = info["oid"]
    @message = info["message"]
    @target_oid = info["target"]
    @target_type = info["target_type"]
    @author_name, @author_email, @authored_date_value = info["tagger"]

    # `info["signature"]` is legacy, but we're avoiding busting the cache.
    @has_signature = info["has_signature"] || !!info["signature"]
  end

  def global_id
    "#{repository.id}:#{oid}"
  end

  # Public: Time object representing when the tag was created.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def authored_date
    @authored_date ||=
      case @authored_date_value
      when Array
        unixtime_to_time(@authored_date_value)
      when String
        Time.iso8601(@authored_date_value)
      end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
  alias date authored_date

  # Conforming to the standard way that next/legacy GlobalIDs are determined.
  alias_method :created_at, :authored_date

  # Public: The user that authored the tag.
  def author
    return @author if defined?(@author)
    @author = User.find_by_email(author_email)
  end
  attr_writer :author

  def author_actor
    GitActor.new(email: author_email, name: author_name, time: date, repository: repository)
  end

  # Users for signature verification.
  alias_method :signer_email, :author_email

  # Public: The tag's short message. This is the first line of the message.
  #
  # Returns a string single line message.
  def short_message
    @short_message ||= message.to_s.lstrip.split("\n", 2).first
  end

  # The HTML Pipeline context hash used when turning commit messages into HTML.
  def message_context
    @message_context ||= super.update(current_user: author)
  end

  # Public: The tag's target object.
  #
  # Returns a Commit, Tag, Tree, or Blob. Almost always a Commit.
  # Raises GitRPC::ObjectMissing when the target object does not exist.
  def target
    @target ||= repository.objects.read(target_oid)
  end

  # The abbreviated oid string. This is the first seven characters of the oid
  # and is usually enough to uniquely identify an object.
  #
  # Returns a seven char hex string.
  def abbreviated_oid
    oid && oid[0, Commit::ABBREVIATED_OID_LENGTH]
  end

  # Internal: Set the Tag's target object. This is typically only used by cache
  # preloading routines when many target objects are loaded in a single
  # round-trip.
  #
  # object - The Commit (or other object) this tag targets. May also be nil to
  #          disassociate the target object or a string oid.
  #
  # Returns object.
  def set_target_object(object)
    if object.respond_to?(:oid)
      @target_oid = object.oid
      @target_type = object.class.to_s.downcase
      @target = object
    else
      @target = nil
      @target_type = nil
      @target_oid = object
    end
  end

  # Internal: Check whether the target object has been set, either via call to
  # set_target_object or by lazy loading on first access.
  def target_acquired?
    !@target.nil?
  end

  # Recursively peel this tag until a commit is found which will be returned
  # (or no commit is found, in which case this returns `nil`).
  def peel_to_commit
    resolved_oid = repository.rpc.peel_to_commit_or_tree(oid)
    repository.commits.find(resolved_oid)
  rescue GitRPC::ObjectMissing, # peel or find
         GitRPC::Failure,       # peel recursion depth limit reached, malformed oid
         GitRPC::InvalidObject  # CommitsCollection#find if peel resolves to tree
    nil
  end

  def inspect
    %(#<Tag #{repository.name_with_owner} #{name.inspect} #{message.inspect} @author=#{author.to_s.inspect} @date=#{authored_date.inspect}>)
  end

  # Equality is based on oid
  def ==(other)
    self.class == other.class &&
    oid == other.oid
  end
  alias_method :eql?, :==

  def hash
    oid.hash
  end

  def async_signature
    return @async_signature if defined?(@async_signature)
    @async_signature = Platform::Loaders::GitSignature.load(self)
  end

  def async_verification_status
    @async_verification_status ||= Promise.all([async_signature, author_actor.async_user]).then do |signature, author|
      next Promise.resolve(:unsigned) unless author
      next Promise.resolve(:verified) if signature&.verified_signature?

      Platform::Loaders::Configuration.load(author, :commit_verification_status_enabled?).then do |setting_enabled|
        setting_enabled ? :unverified : :unsigned
      end
    end
  end

  def verification_status
    async_verification_status.sync
  end
end
